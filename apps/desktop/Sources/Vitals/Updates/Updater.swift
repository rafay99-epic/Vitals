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
        /// Monotonic CI build number, parsed from the release name. 0 when absent
        /// (e.g. Stable releases, which order by version instead).
        var buildNumber: Int = 0

        /// What to show the user: the version, plus the build number for Nightly.
        var displayVersion: String {
            buildNumber > 0 ? "\(version) (build \(buildNumber))" : version
        }
    }

    struct UpdateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    nonisolated static let repository = "rafay99-epic/Vitals"
    nonisolated static let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    /// This build's CI build number (`VitalsBuildNumber`), used to order Nightly
    /// pre-releases. 0 for local builds — so a local Nightly build always sees the
    /// published pre-release as newer and can pull the official one.
    nonisolated static let currentBuildNumber = Int(Bundle.main.infoDictionary?["VitalsBuildNumber"] as? String ?? "") ?? 0
    /// Replace the actual running bundle (wherever it lives), not a hardcoded
    /// path — so an app launched from a non-standard location updates in place.
    nonisolated private static let installPath = Bundle.main.bundlePath
    /// The DMG asset this channel installs (nil for Dev, which never publishes),
    /// and the app bundle inside it.
    nonisolated static var assetName: String? { Channel.current.assetName }
    nonisolated static var bundleInImage: String { "\(Channel.current.displayName).app" }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    private let notifications = NotificationManager()
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var notifiedVersion: String?
    private static let checkInterval: TimeInterval = 6 * 3600
    /// Don't re-check on every refocus — only if the last check is older than this.
    private static let activationRecheckAfter: TimeInterval = 30 * 60

    var isBusy: Bool {
        status == .checking || status == .downloading || status == .installing
    }

    /// Checks at launch, every 6 hours, and when the user returns to the app
    /// (throttled), while the automatic toggle is on. Each channel tracks its
    /// own feed: Stable → the latest release, Nightly → the latest pre-release.
    /// Dev has no feed, so this is a no-op there.
    func startAutomaticChecks(settings: AppSettings) {
        guard Channel.current.updatesEnabled else { return }
        settings.$autoUpdateCheck
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.timer?.invalidate()
                self.timer = nil
                if let observer = self.activationObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.activationObserver = nil
                }
                guard enabled else { return }
                // Make update notifications actually deliverable: permission used
                // to be requested only when overheat alerts were on, so with those
                // off the "update available" notification was silently dropped.
                self.notifications.requestAuthorizationIfNeeded()
                Task { await self.check(userInitiated: false) }
                let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor in await self?.check(userInitiated: false) }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
                // Re-check when the app is brought back to the foreground, so a
                // release published while it was open (or idle) surfaces promptly.
                self.activationObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in await self?.checkOnActivation() }
                }
            }
            .store(in: &cancellables)
    }

    /// A check triggered by returning to the app, throttled so refocusing the
    /// window doesn't hammer GitHub.
    private func checkOnActivation() async {
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.activationRecheckAfter { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        guard Channel.current.updatesEnabled else { status = .idle; return }
        guard !isBusy else { return }
        status = .checking
        Log.debug(.updater, "checking for updates (userInitiated: \(userInitiated))")
        do {
            let release = try await Self.fetchLatestRelease()
            lastChecked = Date()
            if let release, Self.isNewer(release) {
                Log.notice(.updater, "update available: \(release.displayVersion) (current \(Self.currentVersion))")
                status = .available(release)
                if !userInitiated, notifiedVersion != release.tag + "#\(release.buildNumber)" {
                    notifiedVersion = release.tag + "#\(release.buildNumber)"
                    notifications.send(
                        title: "\(Channel.current.displayName) \(release.displayVersion) is available",
                        body: "Open \(Channel.current.displayName) and click Install Update.",
                        id: "vitals.update"
                    )
                }
            } else {
                status = .upToDate
            }
        } catch {
            Log.error(.updater, "update check failed", error: error)
            status = .failed(error.localizedDescription)
        }
    }

    /// Is `release` newer than what's installed? Stable compares the numeric
    /// version; Nightly compares the monotonic CI build number (the pre-release
    /// feed reuses its tag, so the version string alone can't order builds). Dev
    /// never updates.
    nonisolated static func isNewer(_ release: Release) -> Bool {
        switch Channel.current {
        case .stable:  return isVersion(release.version, newerThan: currentVersion)
        case .nightly: return release.buildNumber > currentBuildNumber
        case .dev:     return false
        }
    }

    func downloadAndInstall() async {
        guard case .available(let release) = status else { return }
        status = .downloading
        Log.notice(.updater, "downloading update \(release.displayVersion)")
        do {
            let dmg = try await Self.download(release)
            status = .installing
            Log.notice(.updater, "installing update \(release.displayVersion)")
            try await Self.install(dmgAt: dmg)
            // Hand off to the freshly installed copy and exit this one.
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/zsh")
            relauncher.arguments = ["-c", "sleep 1; /usr/bin/open '\(Self.installPath)'"]
            do {
                try relauncher.run()
            } catch {
                Log.error(.updater, "couldn't launch the relauncher after install — the app will quit without reopening", error: error)
            }
            NSApp.terminate(nil)
        } catch {
            Log.error(.updater, "download/install failed", error: error)
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - GitHub API

    private struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let url: String
        }
        let tagName: String
        let name: String?
        let prerelease: Bool?
        let draft: Bool?
        let assets: [Asset]
    }

    /// Stable tracks the latest published release; Nightly tracks the newest
    /// pre-release (the feed `nightly.yml` publishes). Dev has no feed.
    nonisolated static func fetchLatestRelease() async throws -> Release? {
        guard Channel.current.updatesEnabled else { return nil }
        return Channel.current.isPrerelease ? try await fetchLatestPrerelease() : try await fetchStableRelease()
    }

    nonisolated private static func fetchStableRelease() async throws -> Release? {
        let endpoint = "https://api.github.com/repos/\(repository)/releases/latest"
        guard let data = try await get(endpoint) else { return nil }
        let api = try jsonDecoder().decode(APIRelease.self, from: data)
        return release(from: api)
    }

    nonisolated private static func fetchLatestPrerelease() async throws -> Release? {
        // The list is newest-first; take the first published pre-release carrying
        // a Nightly DMG. Skip drafts — they're visible to maintainers but aren't
        // released, and the backend (convex/lib/github.ts) excludes them too.
        let endpoint = "https://api.github.com/repos/\(repository)/releases?per_page=30"
        guard let data = try await get(endpoint) else { return nil }
        let releases = try jsonDecoder().decode([APIRelease].self, from: data)
        for api in releases where (api.prerelease ?? false) && !(api.draft ?? false) {
            if let release = release(from: api) { return release }
        }
        return nil  // no Nightly pre-release published yet
    }

    /// Shared GET with auth + status handling. Returns nil for a 404 "nothing
    /// published yet" once we know the token can see the (private) repo.
    nonisolated private static func get(_ urlString: String) async throws -> Data? {
        let token = githubToken()
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError(message: "Unexpected response from GitHub.")
        }
        switch http.statusCode {
        case 200: return data
        case 404 where token == nil:
            throw UpdateError(message: "Can't see the private repository. Install GitHub CLI and run “gh auth login”.")
        case 404: return nil  // nothing published yet
        default: throw UpdateError(message: "GitHub returned HTTP \(http.statusCode).")
        }
    }

    nonisolated private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Build a `Release` from an API payload, matching **exactly** this channel's
    /// DMG. No fallback to an arbitrary `.dmg`: the Nightly feed must ignore a
    /// leftover Stable/Dev asset (e.g. an old `Vitals-Dev.dmg` pre-release), or it
    /// would offer a cross-channel build. Returns nil if the channel's asset isn't
    /// present (Dev has none and never reaches here).
    nonisolated private static func release(from api: APIRelease) -> Release? {
        guard let assetName, let asset = api.assets.first(where: { $0.name == assetName }) else { return nil }
        let version = api.tagName.hasPrefix("v") ? String(api.tagName.dropFirst()) : api.tagName
        return Release(version: version, tag: api.tagName, assetURL: asset.url,
                       assetName: asset.name, buildNumber: buildNumber(in: api.name))
    }

    /// Parse the monotonic build number out of a release name like
    /// "Vitals Nightly · build 42". 0 when absent.
    nonisolated static func buildNumber(in name: String?) -> Int {
        guard let name,
              let range = name.range(of: #"build (\d+)"#, options: .regularExpression) else { return 0 }
        return Int(name[range].dropFirst("build ".count)) ?? 0
    }

    nonisolated static func download(_ release: Release) async throws -> URL {
        // assetURL comes from the GitHub API payload — never force-unwrap it.
        guard let assetURL = URL(string: release.assetURL) else {
            throw UpdateError(message: "The release has an invalid download URL.")
        }
        var request = URLRequest(url: assetURL)
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

        let source = mountPoint.appendingPathComponent(bundleInImage)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError(message: "The update image doesn't contain \(bundleInImage).")
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
            guard waitUntilExit(process, timeout: 10) else { continue }  // a wedged `gh` mustn't hang the update check
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
        guard waitUntilExit(process, timeout: 60) else {
            throw UpdateError(message: "\(path) timed out and was stopped.")
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError(message: message.isEmpty ? "\(path) exited with \(process.terminationStatus)" : message)
        }
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Waits for `process` up to `timeout` seconds. Returns true if it exited
    /// on its own; on overrun it terminates (then SIGKILLs) the process and
    /// returns false, so a hung `gh`/`hdiutil`/`ditto` can never block forever.
    @discardableResult
    nonisolated private static func waitUntilExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        // Close the race where the process exits before the handler is attached.
        if !process.isRunning { done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return false
        }
        return true
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
