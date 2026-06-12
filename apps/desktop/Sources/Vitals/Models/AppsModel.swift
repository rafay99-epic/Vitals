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

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isScanning = false
    @Published var selection: Set<URL> = []
    @Published var searchText = ""
    @Published var staged: StagedUninstall?
    @Published private(set) var isPreparingUninstall = false
    @Published private(set) var lastOutcome: AppUninstaller.Outcome?

    private let inventory = AppInventory()
    private var sizeTask: Task<Void, Never>?

    var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.bundleID?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var selectedApps: [InstalledApp] {
        apps.filter { selection.contains($0.id) }
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

    private func computeSizes() {
        let urls = apps.map(\.id)
        sizeTask = Task {
            for await (url, size) in inventory.sizes(for: urls) {
                guard !Task.isCancelled else { return }
                if let index = apps.firstIndex(where: { $0.id == url }) {
                    apps[index].sizeBytes = size
                }
            }
        }
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
