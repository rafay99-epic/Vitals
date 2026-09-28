import Foundation
import SwiftUI

/// State for the Applications section: installed apps, selection, and the
/// staged uninstall awaiting confirmation.
@MainActor
@Observable
final class AppsModel {
    struct StagedUninstall: Identifiable {
        let id = UUID()
        var apps: [InstalledApp]
        var leftovers: [URL: [Leftover]]   // keyed by app bundle URL
        var casks: [URL: String] = [:]     // app URL → Homebrew cask token
        var systemExtensions: [URL: [URL]] = [:]  // app URL → orphaned .systemextension
        var bundlesNeedingAdmin: Set<URL> = []  // root-owned bundles that can't be trashed
        var excluded: Set<URL> = []        // leftovers the user unchecked

        var totalBytes: UInt64 {
            apps.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
                + leftovers.values.joined().filter { !excluded.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
        }

        /// Removal needs the admin prompt and is permanent: a system-domain
        /// leftover or a root-owned bundle.
        var needsAdmin: Bool {
            !bundlesNeedingAdmin.isEmpty
                || leftovers.values.joined().contains { $0.requiresAdmin && !excluded.contains($0.id) }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case name, size
        var id: String { rawValue }
        var label: String { self == .name ? "Name" : "Size" }
    }

    /// Live progress for a running uninstall, updated between each step of
    /// `executeStagedUninstall`.
    struct UninstallProgress {
        enum Phase: Equatable {
            case quitting(String)
            case removingFiles(String)
            case homebrew(String)
            case awaitingAdmin
            case finishing

            var label: String {
                switch self {
                case .quitting(let name):      return "Quitting \(name)…"
                case .removingFiles(let name): return "Removing \(name) and its files…"
                case .homebrew(let name):      return "Uninstalling \(name) with Homebrew…"
                case .awaitingAdmin:           return "Enter your administrator password to remove system files…"
                case .finishing:               return "Finishing up…"
                }
            }
        }

        var completedApps: Int
        let totalApps: Int
        var phase: Phase
        var results: [AppResult] = []

        /// App-granular fill for the determinate bar (multi-app removals).
        var fraction: Double { totalApps > 0 ? Double(completedApps) / Double(totalApps) : 0 }
    }

    /// An app's outcome, shown in the progress list as it lands.
    struct AppResult: Identifiable {
        enum Outcome: Equatable {
            case trashed(items: Int, bytes: UInt64)
            case homebrew
            /// Queued for the end-of-batch admin removal, not yet removed.
            case pendingAdmin
            case removedViaAdmin
            case failed(items: Int)
        }
        let id: URL
        let name: String
        var outcome: Outcome
    }

    private(set) var apps: [InstalledApp] = []
    private(set) var isScanning = false
    var selection: Set<URL> = []
    var searchText = ""
    var sortOrder: SortOrder = .name
    var staged: StagedUninstall?
    private(set) var isPreparingUninstall = false
    /// Non-nil while an uninstall runs; the sheet (bound to `staged`) shows it.
    private(set) var uninstallProgress: UninstallProgress?
    private(set) var lastOutcome: AppUninstaller.Outcome?
    /// Set when /Applications itself couldn't be read, as opposed to nothing removable.
    private(set) var loadError: String?

    private let inventory = AppInventory()
    @ObservationIgnored private var sizeTask: Task<Void, Never>?

    var filteredApps: [InstalledApp] {
        var result = apps
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || ($0.bundleID?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        if sortOrder == .size {
            result = result.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        }
        return result
    }

    var selectedApps: [InstalledApp] {
        apps.filter { $0.protectedReason == nil && selection.contains($0.id) }
    }

    var selectedBytes: UInt64 {
        selectedApps.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    var totalBytes: UInt64 {
        apps.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    var runningCount: Int {
        apps.filter(\.isRunning).count
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        loadError = nil
        selection.removeAll()
        sizeTask?.cancel()
        Task {
            var found = await inventory.scan()
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            for index in found.indices {
                if let bundleID = found[index].bundleID {
                    found[index].isRunning = running.contains(bundleID)
                }
            }
            apps = found
            if found.isEmpty, !FileManager.default.isReadableFile(atPath: "/Applications") {
                loadError = "Vitals couldn't read your Applications folder."
            }
            isScanning = false
            computeSizes()
        }
    }

    deinit {
        sizeTask?.cancel()
    }

    /// Batched: publishing each streamed size would re-render the list per app.
    private func computeSizes() {
        let urls = apps.map(\.id)
        sizeTask = Task { [weak self] in
            guard let self else { return }
            var buffer: [URL: UInt64] = [:]
            for await (url, size) in inventory.sizes(for: urls) {
                if Task.isCancelled { return }
                buffer[url] = size
                if buffer.count >= 10 {
                    applySizes(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            applySizes(buffer)
        }
    }

    private func applySizes(_ sizes: [URL: UInt64]) {
        guard !sizes.isEmpty else { return }
        var updated = apps
        for index in updated.indices {
            if let size = sizes[updated[index].id] {
                updated[index].sizeBytes = size
            }
        }
        apps = updated
    }

    /// Scans leftovers off the main actor and stages the confirmation sheet.
    func prepareUninstall() {
        let targets = selectedApps
        guard !targets.isEmpty, !isPreparingUninstall else { return }
        isPreparingUninstall = true
        Log.debug(.uninstall, "preparing uninstall for \(targets.count) app(s)")
        Task {
            let casksList = await Task.detached(priority: .userInitiated) {
                LeftoverScanner.installedCaskTokens()
            }.value
            var leftovers: [URL: [Leftover]] = [:]
            var casks: [URL: String] = [:]
            var systemExtensions: [URL: [URL]] = [:]
            let scanned = await withTaskGroup(of: (URL, [Leftover], [URL]).self) { group in
                for app in targets {
                    let bundleID = app.bundleID
                    let name = app.name
                    let url = app.id
                    group.addTask(priority: .userInitiated) {
                        (url,
                         LeftoverScanner.scan(bundleID: bundleID, appName: name, appURL: url),
                         LeftoverScanner.systemExtensions(bundleID: bundleID))
                    }
                }
                var out: [(URL, [Leftover], [URL])] = []
                for await result in group { out.append(result) }
                return out
            }
            for (url, found, extensions) in scanned {
                leftovers[url] = found
                if !extensions.isEmpty { systemExtensions[url] = extensions }
            }
            for app in targets {
                guard let candidate = LeftoverScanner.homebrewCask(
                    appName: app.name, installedCasks: casksList
                ) else { continue }
                let ownsBundle = await Task.detached(priority: .userInitiated) {
                    LeftoverScanner.caskOwns(appURL: app.id, token: candidate)
                }.value
                if ownsBundle { casks[app.id] = candidate }
            }
            // Root-owned (pkg-installed) bundles can't be trashed, so they need
            // admin. Cask bundles are excluded: brew removes those.
            let needAdmin = Set(targets.map(\.id).filter { casks[$0] == nil && AppUninstaller.bundleNeedsAdmin($0) })
            staged = StagedUninstall(
                apps: targets, leftovers: leftovers, casks: casks,
                systemExtensions: systemExtensions, bundlesNeedingAdmin: needAdmin
            )
            isPreparingUninstall = false
        }
    }

    /// Quits running apps, hands casks to brew, trashes user-domain files, clears
    /// the prefs domain, then removes every system-domain path in one admin prompt.
    func executeStagedUninstall() {
        guard let staged, uninstallProgress == nil else { return }
        guard staged.apps.allSatisfy({
            $0.protectedReason == nil && !AppInventory.isProtected(bundleID: $0.bundleID, url: $0.id)
        }) else {
            Log.error(.uninstall, "refusing to uninstall a protected application")
            self.staged = nil
            return
        }
        // `staged` stays set so the sheet swaps to progress with no gap. Seeded
        // with the first app's phase so it never flashes "Finishing up…".
        uninstallProgress = UninstallProgress(completedApps: 0, totalApps: staged.apps.count,
                                              phase: .quitting(staged.apps.first?.name ?? ""))
        Task {
            var combined = AppUninstaller.Outcome()
            var systemPaths: [(url: URL, bytes: UInt64)] = []

            for app in staged.apps {
                uninstallProgress?.phase = .quitting(app.name)
                if let running = AppUninstaller.runningApplication(bundleID: app.bundleID) {
                    await Self.quit(running)
                }

                let keep = staged.excluded
                let leftovers = (staged.leftovers[app.id] ?? []).filter { !keep.contains($0.id) }

                var bundleHandledByBrew = false
                if let cask = staged.casks[app.id] {
                    uninstallProgress?.phase = .homebrew(app.name)
                    let removed = await Task.detached(priority: .userInitiated) {
                        AppUninstaller.homebrewUninstall(cask: cask)
                    }.value
                    if removed { bundleHandledByBrew = true; combined.caskUninstalled += 1 }
                }

                // A root-owned bundle skips the doomed Trash attempt.
                let bundleViaAdmin = !bundleHandledByBrew && staged.bundlesNeedingAdmin.contains(app.id)
                if bundleViaAdmin {
                    systemPaths.append((app.id, app.sizeBytes ?? 0))
                }

                uninstallProgress?.phase = .removingFiles(app.name)
                let outcome = await Task.detached(priority: .userInitiated) {
                    AppUninstaller.uninstall(app: app, leftovers: leftovers, skipBundle: bundleHandledByBrew || bundleViaAdmin)
                }.value
                combined.trashed += outcome.trashed
                combined.failures += outcome.failures
                combined.freedBytes += outcome.freedBytes

                // Trash blocked by App Management falls back to admin.
                for bundle in outcome.failedBundles {
                    systemPaths.append((bundle, app.sizeBytes ?? 0))
                }

                let bundleID = app.bundleID
                await Task.detached(priority: .utility) {
                    AppUninstaller.clearDefaults(bundleID: bundleID)
                }.value

                for leftover in leftovers where leftover.requiresAdmin {
                    systemPaths.append((leftover.id, leftover.sizeBytes))
                }

                uninstallProgress?.results.append(appResult(for: app, outcome: outcome,
                                                            cask: bundleHandledByBrew,
                                                            viaAdmin: bundleViaAdmin))
                uninstallProgress?.completedApps += 1
            }

            // Dedup: two apps can share a system path, which would double-count the summary.
            var seenSystemPaths = Set<String>()
            let uniqueSystemPaths = systemPaths.filter {
                seenSystemPaths.insert($0.url.standardizedFileURL.path).inserted
            }
            if !uniqueSystemPaths.isEmpty,
               let script = AppUninstaller.systemRemovalScript(for: uniqueSystemPaths.map(\.url)) {
                uninstallProgress?.phase = .awaitingAdmin
                do {
                    try await PrivilegedShell.runAsAdmin(
                        script,
                        prompt: "Vitals needs administrator access to remove system-level leftover files."
                    )
                    // The script is best-effort (`rm … || true`): credit only paths gone from disk.
                    let fm = FileManager.default
                    let removed = uniqueSystemPaths.filter { !fm.fileExists(atPath: $0.url.path) }
                    combined.usedAdmin = true
                    combined.systemRemoved = removed.count
                    combined.freedBytes += removed.reduce(0) { $0 + $1.bytes }
                } catch let error as PrivilegedShell.AdminError {
                    if error.cancelled {
                        combined.adminCancelled = true
                    } else {
                        Log.error(.uninstall, "privileged leftover removal failed — \(error.message)")
                        combined.errorMessage = error.message
                    }
                } catch {
                    Log.error(.uninstall, "privileged leftover removal failed", error: error)
                    combined.errorMessage = error.localizedDescription
                }
            }

            // Settle pending rows from the disk too, for the same best-effort reason.
            if var progress = uninstallProgress {
                let fm = FileManager.default
                for index in progress.results.indices where progress.results[index].outcome == .pendingAdmin {
                    if !fm.fileExists(atPath: progress.results[index].id.path) {
                        progress.results[index].outcome = .removedViaAdmin
                    }
                }
                uninstallProgress = progress
            }

            uninstallProgress?.phase = .finishing
            Log.notice(.uninstall, "uninstall finished: \(combined.trashed.count) trashed, \(combined.systemRemoved) system, \(ByteCountFormatter.string(fromByteCount: Int64(combined.freedBytes), countStyle: .file)) freed")
            lastOutcome = combined
            uninstallProgress = nil
            refresh()
        }
    }

    /// Admin-bound bundles report `pendingAdmin`: removal happens in the batch pass afterward.
    private func appResult(for app: InstalledApp, outcome: AppUninstaller.Outcome,
                           cask: Bool, viaAdmin: Bool) -> AppResult {
        let result: AppResult.Outcome
        if cask {
            result = .homebrew
        } else if viaAdmin || !outcome.failedBundles.isEmpty {
            result = .pendingAdmin
        } else if outcome.failures.isEmpty {
            result = .trashed(items: outcome.trashed.count, bytes: outcome.freedBytes)
        } else {
            result = .failed(items: outcome.failures.count)
        }
        return AppResult(id: app.id, name: app.name, outcome: result)
    }

    /// Quits gracefully, polling for exit, and force-quits only if the app hangs.
    private static func quit(_ running: NSRunningApplication) async {
        running.terminate()
        var exited = false
        for _ in 0..<20 {               // up to ~2s of graceful wait
            if running.isTerminated { exited = true; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !exited {
            running.forceTerminate()
            for _ in 0..<5 {            // up to ~0.5s after a force-quit
                if running.isTerminated { exited = true; break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        // macOS can hold the app's files open briefly after exit; trashing at once reports "in use".
        if exited { try? await Task.sleep(for: .milliseconds(250)) }
    }

    /// Dismisses the finished-uninstall summary and tears down the sheet.
    func finishUninstall() {
        staged = nil
        lastOutcome = nil
        uninstallProgress = nil
    }
}
