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

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isScanning = false
    @Published var selection: Set<URL> = []
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .name
    @Published var staged: StagedUninstall?
    @Published private(set) var isPreparingUninstall = false
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
        Task {
            let casksList = await Task.detached(priority: .userInitiated) {
                LeftoverScanner.installedCaskTokens()
            }.value
            var leftovers: [URL: [Leftover]] = [:]
            var casks: [URL: String] = [:]
            var systemExtensions: [URL: [URL]] = [:]
            for app in targets {
                let bundleID = app.bundleID
                let name = app.name
                let url = app.id
                leftovers[url] = await Task.detached(priority: .userInitiated) {
                    LeftoverScanner.scan(bundleID: bundleID, appName: name, appURL: url)
                }.value
                if let cask = LeftoverScanner.homebrewCask(appName: name, installedCasks: casksList) {
                    casks[url] = cask
                }
                let extensions = await Task.detached(priority: .utility) {
                    LeftoverScanner.systemExtensions(bundleID: bundleID)
                }.value
                if !extensions.isEmpty { systemExtensions[url] = extensions }
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
        guard let staged else { return }
        self.staged = nil
        Task {
            var combined = AppUninstaller.Outcome()
            var systemPaths: [URL] = []
            var systemBytes: UInt64 = 0

            for app in staged.apps {
                if let running = AppUninstaller.runningApplication(bundleID: app.bundleID) {
                    running.terminate()
                    try? await Task.sleep(for: .milliseconds(800))
                    if !running.isTerminated { running.forceTerminate() }
                    try? await Task.sleep(for: .milliseconds(400))
                }

                let keep = staged.excluded
                let leftovers = (staged.leftovers[app.id] ?? []).filter { !keep.contains($0.id) }

                var bundleHandledByBrew = false
                if let cask = staged.casks[app.id] {
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
            }

            // One admin prompt for every system-domain leftover across the batch.
            if !systemPaths.isEmpty,
               let script = AppUninstaller.systemRemovalScript(for: systemPaths) {
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

            lastOutcome = combined
            Log.notice(.uninstall, "uninstall finished: \(combined.trashed.count) trashed, \(combined.systemRemoved) system, \(ByteCountFormatter.string(fromByteCount: Int64(combined.freedBytes), countStyle: .file)) freed")
            refresh()
        }
    }

    func dismissOutcome() {
        lastOutcome = nil
    }
}
