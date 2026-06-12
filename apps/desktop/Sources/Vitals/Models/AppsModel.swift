import Foundation
import SwiftUI

/// State for the Applications tab: the installed-app list, selection, and
/// the staged uninstall (scan results awaiting user confirmation).
@MainActor
final class AppsModel: ObservableObject {
    struct StagedUninstall: Identifiable {
        let id = UUID()
        var apps: [InstalledApp]
        var leftovers: [URL: [Leftover]]  // keyed by app bundle URL
        var excluded: Set<URL> = []       // leftovers the user unchecked

        var totalBytes: UInt64 {
            apps.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
                + leftovers.values.joined().filter { !excluded.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
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
            var leftovers: [URL: [Leftover]] = [:]
            for app in targets {
                let bundleID = app.bundleID
                let name = app.name
                leftovers[app.id] = await Task.detached(priority: .userInitiated) {
                    LeftoverScanner.scan(bundleID: bundleID, appName: name)
                }.value
            }
            staged = StagedUninstall(apps: targets, leftovers: leftovers)
            isPreparingUninstall = false
        }
    }

    /// Runs the staged uninstall. Running apps are terminated first (the
    /// confirmation sheet warned about them).
    func executeStagedUninstall() {
        guard let staged else { return }
        self.staged = nil
        Task {
            var combined = AppUninstaller.Outcome()
            for app in staged.apps {
                if let running = AppUninstaller.runningApplication(bundleID: app.bundleID) {
                    running.terminate()
                    // Give it a moment; escalate politely if it ignores us.
                    try? await Task.sleep(for: .milliseconds(800))
                    if !running.isTerminated { running.forceTerminate() }
                    try? await Task.sleep(for: .milliseconds(400))
                }
                let keep = staged.excluded
                let leftovers = (staged.leftovers[app.id] ?? []).filter { !keep.contains($0.id) }
                let outcome = await Task.detached(priority: .userInitiated) {
                    AppUninstaller.uninstall(app: app, leftovers: leftovers)
                }.value
                combined.trashed += outcome.trashed
                combined.failures += outcome.failures
                combined.freedBytes += outcome.freedBytes
            }
            lastOutcome = combined
            refresh()
        }
    }

    func dismissOutcome() {
        lastOutcome = nil
    }
}
