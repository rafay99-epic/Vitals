import Foundation
import AppKit
import Combine

/// Checks GitHub Releases for newer builds, downloads the DMG, and swaps the
/// installed app. The repository is private, so requests authenticate with
/// the token from the locally signed-in GitHub CLI (`gh auth token`).
@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let tag: String
        let assetURL: String
        let assetName: String
    }

    struct UpdateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    nonisolated static let repository = "rafay99-epic/Vitals"
    nonisolated static let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    nonisolated private static let installPath = "/Applications/Vitals.app"

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    private let notifications = NotificationManager()
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var notifiedVersion: String?
    private static let checkInterval: TimeInterval = 6 * 3600

    var isBusy: Bool {
        status == .checking || status == .downloading || status == .installing
    }

    /// Checks at launch and every 6 hours while the automatic toggle is on.
    func startAutomaticChecks(settings: AppSettings) {
        settings.$autoUpdateCheck
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.timer?.invalidate()
                self.timer = nil
                guard enabled else { return }
                Task { await self.check(userInitiated: false) }
                let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor in await self?.check(userInitiated: false) }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
            .store(in: &cancellables)
    }

    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        status = .checking
        do {
            let release = try await Self.fetchLatestRelease()
            lastChecked = Date()
            if let release, Self.isVersion(release.version, newerThan: Self.currentVersion) {
                status = .available(release)
                if !userInitiated, notifiedVersion != release.version {
                    notifiedVersion = release.version
                    notifications.send(
                        title: "Vitals \(release.version) is available",
                        body: "Open Vitals and click Install Update to upgrade from \(Self.currentVersion).",
                        id: "vitals.update"
                    )
                }
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func downloadAndInstall() async {
        guard case .available(let release) = status else { return }
        status = .downloading
        do {
            let dmg = try await Self.download(release)
            status = .installing
            try await Self.install(dmgAt: dmg)
            // Hand off to the freshly installed copy and exit this one.
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/zsh")
            relauncher.arguments = ["-c", "sleep 1; /usr/bin/open '\(Self.installPath)'"]
            try? relauncher.run()
            NSApp.terminate(nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - GitHub API

    nonisolated static func fetchLatestRelease() async throws -> Release? {
        let token = githubToken()
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError(message: "Unexpected response from GitHub.")
        }
        switch http.statusCode {
        case 200:
            break
        case 404 where token == nil:
            throw UpdateError(message: "Can't see the private repository. Install GitHub CLI and run “gh auth login”.")
        case 404:
            return nil  // no releases published yet
        default:
            throw UpdateError(message: "GitHub returned HTTP \(http.statusCode).")
        }

        struct APIRelease: Decodable {
            struct Asset: Decodable {
                let name: String
                let url: String
            }
            let tagName: String
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let api = try decoder.decode(APIRelease.self, from: data)
        guard let asset = api.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw UpdateError(message: "Release \(api.tagName) has no DMG asset.")
        }
        let version = api.tagName.hasPrefix("v") ? String(api.tagName.dropFirst()) : api.tagName
        return Release(version: version, tag: api.tagName, assetURL: asset.url, assetName: asset.name)
    }

    nonisolated static func download(_ release: Release) async throws -> URL {
        var request = URLRequest(url: URL(string: release.assetURL)!)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token = githubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // GitHub redirects asset downloads to S3, which rejects requests that
        // still carry the Authorization header — strip it on redirect.
        // download(for:) streams to disk, so the DMG never sits in memory.
        let (tempFile, response) = try await URLSession.shared.download(for: request, delegate: RedirectSanitizer())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempFile)
            throw UpdateError(message: "Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vitals-\(release.version).dmg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }

    nonisolated static func install(dmgAt dmg: URL) async throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitals-update-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try runTool("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path])
        defer {
            _ = try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? FileManager.default.removeItem(at: dmg)
        }

        let source = mountPoint.appendingPathComponent("Vitals.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError(message: "The update image doesn't contain Vitals.app.")
        }
        if FileManager.default.fileExists(atPath: installPath) {
            try FileManager.default.removeItem(atPath: installPath)
        }
        try runTool("/usr/bin/ditto", [source.path, installPath])
    }

    // MARK: - Helpers

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func components(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = components(candidate)
        let b = components(current)
        for index in 0..<max(a.count, b.count) {
            let lhs = index < a.count ? a[index] : 0
            let rhs = index < b.count ? b[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    nonisolated static func githubToken() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        for gh in candidates where FileManager.default.isExecutableFile(atPath: gh) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gh)
            process.arguments = ["auth", "token"]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { continue }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { continue }
            let token = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let token, !token.isEmpty { return token }
        }
        return nil
    }

    @discardableResult
    nonisolated private static func runTool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError(message: message.isEmpty ? "\(path) exited with \(process.terminationStatus)" : message)
        }
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private final class RedirectSanitizer: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            var sanitized = request
            sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
            return sanitized
        }
    }
}
