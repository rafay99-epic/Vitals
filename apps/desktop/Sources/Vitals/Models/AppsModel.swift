import Foundation
import SwiftUI

/// State for the Applications tab: the installed-app list, selection, and
/// the staged uninstall (scan results awaiting user confirmation).
@MainActor
final class AppsModel: ObservableObject {
    struct StagedUninstall: Identifiable {
        let id = UUID()
        var apps: [InstalledApp]
        var leftovers: [URL: [Leftover]]   // keyed by app bundle URL
        var casks: [URL: String] = [:]     // app URL → Homebrew cask token
        var systemExtensions: [URL: [URL]] = [:]  // app URL → orphaned .systemextension
        var bundlesNeedingAdmin: Set<URL> = []  // app bundles that can't be trashed (root-owned)
        var excluded: Set<URL> = []        // leftovers the user unchecked

        var totalBytes: UInt64 {
            apps.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
                + leftovers.values.joined().filter { !excluded.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
        }

        /// True when removal needs the admin prompt and is permanent — either a
        /// system-domain leftover or a protected (root-owned) app bundle.
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

    /// Live progress for a running uninstall, so the UI shows exactly what's
    /// happening instead of a frozen sheet. Updated on the main actor between
    /// each step of `executeStagedUninstall`.
    struct UninstallProgress {
        /// The current step's human label — the "is this thing stuck?" answer.
        enum Phase: Equatable {
            case quitting(String)
            case removingFiles(String)
            case homebrew(String)
            case awaitingAdmin
            case removingSystem
            case finishing

            var label: String {
                switch self {
                case .quitting(let name):      return "Quitting \(name)…"
                case .removingFiles(let name): return "Removing \(name) and its files…"
                case .homebrew(let name):      return "Uninstalling \(name) with Homebrew…"
                case .awaitingAdmin:           return "Enter your administrator password to remove system files…"
                case .removingSystem:          return "Removing system files…"
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

    /// A finished app's outcome, shown live in the progress list as it lands.
    struct AppResult: Identifiable {
        let id: URL
        let name: String
        let succeeded: Bool
        let detail: String
    }

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isScanning = false
    @Published var selection: Set<URL> = []
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .name
    @Published var staged: StagedUninstall?
    @Published private(set) var isPreparingUninstall = false
    /// Non-nil while an uninstall is actually running — drives the in-sheet
    /// progress view. The sheet stays up (bound to `staged`) and swaps to this.
    @Published private(set) var uninstallProgress: UninstallProgress?
    @Published private(set) var lastOutcome: AppUninstaller.Outcome?
    /// Set when the Applications folder itself couldn't be read — distinguishes
    /// a genuine failure from simply having nothing removable installed.
    @Published private(set) var loadError: String?

    private let inventory = AppInventory()
    private var sizeTask: Task<Void, Never>?

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
        apps.filter { selection.contains($0.id) }
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
            // Empty + unreadable /Applications is a real error; empty + readable
            // just means nothing removable is installed.
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

    /// Sizes stream in as they're computed, but publishing each one would
    /// re-render the whole list per app — batch them instead.
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

    /// Scans leftovers for the selected apps and stages the confirmation
    /// sheet. Heavy filesystem work happens off the main actor.
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
            // Scan every selected app concurrently — each scan is an independent
            // filesystem walk, so a serial loop made multi-select needlessly slow.
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
                if let cask = LeftoverScanner.homebrewCask(appName: app.name, installedCasks: casksList) {
                    casks[app.id] = cask
                }
            }
            // A root-owned bundle (installed by a pkg) can't be trashed — flag it
            // so the sheet shows it's admin/permanent, and the cask-handled ones
            // are excluded (brew removes those).
            let needAdmin = Set(targets.map(\.id).filter { casks[$0] == nil && AppUninstaller.bundleNeedsAdmin($0) })
            staged = StagedUninstall(
                apps: targets, leftovers: leftovers, casks: casks,
                systemExtensions: systemExtensions, bundlesNeedingAdmin: needAdmin
            )
            isPreparingUninstall = false
        }
    }

    /// Runs the staged uninstall. Running apps are terminated first (the
    /// confirmation sheet warned about them). Homebrew casks are handed to
    /// brew, user-domain files go to the Trash, the prefs domain is cleared,
    /// and all system-domain leftovers across every app are removed in a single
    /// administrator prompt at the end.
    func executeStagedUninstall() {
        guard let staged, uninstallProgress == nil else { return }
        // Keep `staged` set so the sheet stays up and swaps to the progress view
        // (no blank gap between confirm and the final summary).
        uninstallProgress = UninstallProgress(completedApps: 0, totalApps: staged.apps.count,
                                              phase: .finishing)
        Task {
            var combined = AppUninstaller.Outcome()
            var systemPaths: [URL] = []
            var systemBytes: UInt64 = 0

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

                // A protected/root-owned bundle skips the (doomed) Trash attempt
                // and goes straight to the admin pass.
                let bundleViaAdmin = !bundleHandledByBrew && staged.bundlesNeedingAdmin.contains(app.id)
                if bundleViaAdmin {
                    systemPaths.append(app.id)
                    systemBytes += app.sizeBytes ?? 0
                }

                uninstallProgress?.phase = .removingFiles(app.name)
                let outcome = await Task.detached(priority: .userInitiated) {
                    AppUninstaller.uninstall(app: app, leftovers: leftovers, skipBundle: bundleHandledByBrew || bundleViaAdmin)
                }.value
                combined.trashed += outcome.trashed
                combined.failures += outcome.failures
                combined.freedBytes += outcome.freedBytes

                // Trash that failed (App-Management-blocked) falls back to admin.
                for bundle in outcome.failedBundles {
                    systemPaths.append(bundle)
                    systemBytes += app.sizeBytes ?? 0
                }

                let bundleID = app.bundleID
                await Task.detached(priority: .utility) {
                    AppUninstaller.clearDefaults(bundleID: bundleID)
                }.value

                for leftover in leftovers where leftover.requiresAdmin {
                    systemPaths.append(leftover.id)
                    systemBytes += leftover.sizeBytes
                }

                // Record this app's outcome live so the user watches the list fill.
                uninstallProgress?.results.append(appResult(for: app, outcome: outcome,
                                                            cask: staged.casks[app.id] != nil,
                                                            viaAdmin: bundleViaAdmin))
                uninstallProgress?.completedApps += 1
            }

            // One admin prompt for every system-domain leftover across the batch.
            if !systemPaths.isEmpty,
               let script = AppUninstaller.systemRemovalScript(for: systemPaths) {
                uninstallProgress?.phase = .awaitingAdmin
                do {
                    try await PrivilegedShell.runAsAdmin(
                        script,
                        prompt: "Vitals needs administrator access to remove system-level leftover files."
                    )
                    combined.usedAdmin = true
                    combined.systemRemoved = systemPaths.count
                    combined.freedBytes += systemBytes
                } catch let error as PrivilegedShell.AdminError {
                    if !error.cancelled {
                        Log.error(.uninstall, "privileged leftover removal failed — \(error.message)")
                        combined.errorMessage = error.message
                    }
                } catch {
                    Log.error(.uninstall, "privileged leftover removal failed", error: error)
                    combined.errorMessage = error.localizedDescription
                }
            }

            uninstallProgress?.phase = .finishing
            Log.notice(.uninstall, "uninstall finished: \(combined.trashed.count) trashed, \(combined.systemRemoved) system, \(ByteCountFormatter.string(fromByteCount: Int64(combined.freedBytes), countStyle: .file)) freed")
            // Hand off to the summary state and rescan the (now shorter) app list.
            lastOutcome = combined
            uninstallProgress = nil
            refresh()
        }
    }

    /// Per-app line for the live results list — succeeded unless a Trash move
    /// failed and didn't fall back to the admin path.
    private func appResult(for app: InstalledApp, outcome: AppUninstaller.Outcome,
                           cask: Bool, viaAdmin: Bool) -> AppResult {
        let succeeded = outcome.failures.isEmpty
        let detail: String
        if cask {
            detail = "Removed with Homebrew"
        } else if viaAdmin || !outcome.failedBundles.isEmpty {
            detail = "Needs your password (system-owned)"
        } else if outcome.failures.isEmpty {
            let count = outcome.trashed.count
            detail = "\(count) item\(count == 1 ? "" : "s") · \(formatBytes(outcome.freedBytes))"
        } else {
            detail = "\(outcome.failures.count) item\(outcome.failures.count == 1 ? "" : "s") couldn't be removed"
        }
        return AppResult(id: app.id, name: app.name, succeeded: succeeded, detail: detail)
    }

    /// Quit a running app, then poll briefly for it to actually exit instead of
    /// sleeping a fixed 1.2s every time — most apps quit in a few hundred ms, so
    /// this returns as soon as they're gone and only escalates if they hang.
    private static func quit(_ running: NSRunningApplication) async {
        running.terminate()
        for _ in 0..<20 {               // up to ~2s of graceful wait
            if running.isTerminated { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        running.forceTerminate()
        for _ in 0..<5 {                // up to ~0.5s after a force-quit
            if running.isTerminated { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Dismisses the finished-uninstall summary and tears down the sheet.
    func finishUninstall() {
        staged = nil
        lastOutcome = nil
        uninstallProgress = nil
    }

    func dismissOutcome() {
        lastOutcome = nil
    }
}
