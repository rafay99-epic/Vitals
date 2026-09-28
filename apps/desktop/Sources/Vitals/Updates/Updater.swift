import Foundation
import AppKit
import Observation

/// Checks GitHub Releases for newer builds, downloads the DMG, and swaps the
/// installed app. The repository is public, so requests are unauthenticated.
@MainActor
@Observable
final class Updater {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        /// Pre-downloaded in the background, waiting for the user to install.
        case readyToInstall(Release)
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
    /// CI build number (`VitalsBuildNumber`), orders Nightly pre-releases. 0 for
    /// local builds, so a local Nightly always sees the published one as newer.
    nonisolated static let currentBuildNumber = Int(Bundle.main.infoDictionary?["VitalsBuildNumber"] as? String ?? "") ?? 0
    /// The running bundle, so an app outside /Applications updates in place.
    nonisolated private static let installPath = Bundle.main.bundlePath
    /// The DMG asset this channel installs (nil for Dev, which never publishes),
    /// and the app bundle inside it.
    nonisolated static var assetName: String? { Channel.current.assetName }
    nonisolated static var bundleInImage: String { "\(Channel.current.displayName).app" }

    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?

    private let notifications = NotificationManager()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var notifiedVersion: String?
    /// Read at check time for `autoDownloadUpdates`.
    @ObservationIgnored private weak var settings: AppSettings?
    /// A DMG already downloaded in the background, waiting to be installed.
    @ObservationIgnored private var pendingDMG: URL?
    private static let checkInterval: TimeInterval = 6 * 3600
    /// Refocus re-checks only if the last check is older than this.
    private static let activationRecheckAfter: TimeInterval = 30 * 60

    var isBusy: Bool {
        status == .checking || status == .downloading || status == .installing
    }

    init() {
        // Notification taps drive the update flow with no window open.
        notifications.onUpdateAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .download: Task { await self.handleDownloadAction() }
            case .install:  Task { await self.handleInstallAction() }
            }
        }
    }

    /// Checks at launch, every 6 hours, and on refocus (throttled) while the
    /// automatic toggle is on. No-op on Dev.
    func startAutomaticChecks(settings: AppSettings) {
        guard Channel.current.updatesEnabled else { return }
        self.settings = settings
        applyAutomaticChecks(settings.autoUpdateCheck)
        observeChanges(of: { settings.autoUpdateCheck }) { [weak self] in self?.applyAutomaticChecks($0) }
    }

    private func applyAutomaticChecks(_ enabled: Bool) {
        self.timer?.invalidate()
        self.timer = nil
        if let observer = self.activationObserver {
            NotificationCenter.default.removeObserver(observer)
            self.activationObserver = nil
        }
        guard enabled else { return }
        self.notifications.requestAuthorizationIfNeeded()
        Task { await self.check(userInitiated: false) }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(userInitiated: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        self.activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.checkOnActivation() }
        }
    }

    /// Throttled so refocusing the window doesn't hammer GitHub.
    private func checkOnActivation() async {
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.activationRecheckAfter { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        guard Channel.current.updatesEnabled else { status = .idle; return }
        guard !isBusy else { return }
        // Captured before `.checking` overwrites it, to detect an already-downloaded build.
        let previous = status
        status = .checking
        Log.debug(.updater, "checking for updates (userInitiated: \(userInitiated))")
        do {
            let release = try await Self.fetchLatestRelease()
            lastChecked = Date()
            if let release, Self.isNewer(release) {
                Log.notice(.updater, "update available: \(release.displayVersion) (current \(Self.currentVersion))")
                // A re-check must not reset `.readyToInstall` and abandon the cached DMG.
                if case .readyToInstall(let pending) = previous,
                   Self.notifyKey(pending) == Self.notifyKey(release) {
                    status = .readyToInstall(pending)
                } else {
                    status = .available(release)
                }
                if !userInitiated, notifiedVersion != Self.notifyKey(release) {
                    notifiedVersion = Self.notifyKey(release)
                    if settings?.autoDownloadUpdates == true {
                        await downloadInBackground(release)
                    } else {
                        notifyUpdateAvailable(release)
                    }
                }
            } else {
                status = .upToDate
            }
        } catch {
            Log.error(.updater, "update check failed", error: error)
            status = .failed(error.localizedDescription)
        }
    }

    /// Stable compares the numeric version; Nightly compares the CI build number,
    /// since its rolling pre-release reuses one tag.
    nonisolated static func isNewer(_ release: Release) -> Bool {
        switch Channel.current {
        case .stable:  return isVersion(release.version, newerThan: currentVersion)
        case .nightly: return release.buildNumber > currentBuildNumber
        case .dev:     return false
        }
    }

    /// Downloads (unless already pre-downloaded) and installs the available release.
    func downloadAndInstall() async {
        let release: Release
        switch status {
        case .available(let r):
            release = r
        case .readyToInstall(let r):
            if let dmg = pendingDMG { await installAndRelaunch(dmgAt: dmg, release: r); return }
            release = r
        default:
            return
        }
        status = .downloading
        Log.notice(.updater, "downloading update \(release.displayVersion)")
        do {
            let dmg = try await Self.download(release)
            await installAndRelaunch(dmgAt: dmg, release: release)
        } catch {
            Log.error(.updater, "download failed", error: error)
            status = .failed(error.localizedDescription)
            notifyFailure(release)
        }
    }

    /// Installs a DMG pre-downloaded by a background check.
    func installPending() async {
        guard case .readyToInstall(let release) = status, let dmg = pendingDMG else { return }
        await installAndRelaunch(dmgAt: dmg, release: release)
    }

    /// Pre-downloads after a background check. On failure, falls back to the
    /// "available" notification so the user can download on demand.
    private func downloadInBackground(_ release: Release) async {
        guard !isBusy else { return }
        status = .downloading
        Log.notice(.updater, "pre-downloading update \(release.displayVersion) in the background")
        do {
            let dmg = try await Self.download(release)
            pendingDMG = dmg
            status = .readyToInstall(release)
            notifyUpdateReady(release)
        } catch {
            Log.error(.updater, "background download failed — offering on-demand download instead", error: error)
            status = .available(release)
            notifyUpdateAvailable(release)
        }
    }

    /// Installs, then launches the new copy and terminates this one.
    private func installAndRelaunch(dmgAt dmg: URL, release: Release) async {
        status = .installing
        Log.notice(.updater, "installing update \(release.displayVersion)")
        do {
            try await Self.install(dmgAt: dmg)
        } catch {
            Log.error(.updater, "install failed", error: error)
            status = .failed(error.localizedDescription)
            notifyFailure(release)
            return
        }
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Bundle path goes in as $0, never interpolated, so a quote in the path can't inject.
        relauncher.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$0\"", Self.installPath]
        do {
            try relauncher.run()
        } catch {
            Log.error(.updater, "couldn't launch the relauncher after install — the app will quit without reopening", error: error)
        }
        NSApp.terminate(nil)
    }

    // MARK: - Notification actions

    /// Re-checks first if the app relaunched since the notification and lost its state.
    private func handleDownloadAction() async {
        NSApp.activate(ignoringOtherApps: true)
        switch status {
        case .available, .readyToInstall: break
        default: await check(userInitiated: true)
        }
        await downloadAndInstall()
    }

    /// Falls back to a fresh download if the pre-downloaded DMG is gone (app relaunched).
    private func handleInstallAction() async {
        NSApp.activate(ignoringOtherApps: true)
        if pendingDMG != nil, case .readyToInstall = status {
            await installPending()
        } else {
            await handleDownloadAction()
        }
    }

    // MARK: - Notifications

    private static func notifyKey(_ release: Release) -> String {
        release.tag + "#\(release.buildNumber)"
    }

    private func notifyUpdateAvailable(_ release: Release) {
        notifications.send(
            title: "\(Channel.current.displayName) \(release.displayVersion) is available",
            body: "Tap Download & Install to update in the background.",
            id: "vitals.update",
            categoryId: NotificationManager.Category.updateAvailable
        )
    }

    private func notifyUpdateReady(_ release: Release) {
        notifications.send(
            title: "\(Channel.current.displayName) \(release.displayVersion) is ready to install",
            body: "Downloaded and ready. Tap Install & Relaunch to finish.",
            id: "vitals.update",
            categoryId: NotificationManager.Category.updateReady
        )
    }

    private func notifyFailure(_ release: Release) {
        notifications.send(
            title: "\(Channel.current.displayName) update failed",
            body: "Couldn't update to \(release.displayVersion). Open \(Channel.current.displayName) → Settings → Updates to try again.",
            id: "vitals.update.failed"
        )
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

    /// Stable: latest release. Nightly: newest pre-release. Dev: none.
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
        // Newest-first. Skip drafts: visible to maintainers but unreleased
        // (convex/lib/github.ts excludes them too).
        let endpoint = "https://api.github.com/repos/\(repository)/releases?per_page=30"
        guard let data = try await get(endpoint) else { return nil }
        let releases = try jsonDecoder().decode([APIRelease].self, from: data)
        for api in releases where (api.prerelease ?? false) && !(api.draft ?? false) {
            if let release = release(from: api) { return release }
        }
        return nil
    }

    /// Shared GET with status handling. Returns nil for a 404 (nothing published yet).
    nonisolated private static func get(_ urlString: String) async throws -> Data? {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError(message: "Unexpected response from GitHub.")
        }
        switch http.statusCode {
        case 200: return data
        case 404: return nil
        default: throw UpdateError(message: "GitHub returned HTTP \(http.statusCode).")
        }
    }

    nonisolated private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Matches exactly this channel's DMG, never any `.dmg`: a leftover asset from
    /// another channel would otherwise offer a cross-channel build.
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
        // assetURL comes from the API payload; never force-unwrap it.
        guard let assetURL = URL(string: release.assetURL) else {
            throw UpdateError(message: "The release has an invalid download URL.")
        }
        var request = URLRequest(url: assetURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        // download(for:) streams to disk, so the DMG never sits in memory.
        let (tempFile, response) = try await URLSession.shared.download(for: request)
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

    /// Numeric compare, so "0.10" is newer than "0.9".
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
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

    /// Returns false after terminating (then SIGKILLing) a process that overruns
    /// `timeout`, so a hung `hdiutil`/`ditto` can't block forever.
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
}
