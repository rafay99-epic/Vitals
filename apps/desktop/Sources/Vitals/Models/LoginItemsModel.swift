import Foundation
import SwiftUI

/// Owns the launch-item list for the Login Items tab. Scans off the main thread
/// and survives tab switches (held by ContentView). Toggling is the only write,
/// and only for the user's own non-Apple agents.
@MainActor
final class LoginItemsModel: ObservableObject {
    @Published private(set) var items: [LaunchItem] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    /// The live resource cost of each item, keyed by `LaunchItem.id`. Populated
    /// after a scan; user agents get a real footprint/CPU or "Not running",
    /// system items stay `.notMeasured`. Honest by construction — no fake numbers.
    @Published private(set) var impact: [LaunchItem.ID: StartupImpact.State] = [:]

    var userItems: [LaunchItem] { items.filter { $0.kind == .userAgent } }
    var systemItems: [LaunchItem] { items.filter { $0.kind != .userAgent } }

    /// Total live footprint of the user's running login agents — the honest
    /// "this is what auto-start is costing you" figure. nil when nothing readable.
    var userFootprintBytes: UInt64? {
        let total = userItems.reduce(UInt64(0)) { sum, item in
            if case .running(let cost) = impact[item.id] { return sum + cost.memoryBytes }
            return sum
        }
        return total > 0 ? total : nil
    }

    func loadIfNeeded() async {
        guard !loaded, !loading else { return }
        await reload()
    }

    func reload() async {
        loading = true
        items = await Task.detached { LaunchItemScanner.scan() }.value
        loading = false
        loaded = true
        await refreshImpact()
    }

    /// Attributes each item to its live process and reads the real cost, off the
    /// main actor. Cheap (one `launchctl list` + a `proc_pid_rusage` per running
    /// user agent), so it re-runs on every scan and manual refresh.
    func refreshImpact() async {
        let current = items
        impact = await Task.detached { () -> [LaunchItem.ID: StartupImpact.State] in
            let pids = LaunchItemScanner.runningPIDs()
            var out: [LaunchItem.ID: StartupImpact.State] = [:]
            for item in current { out[item.id] = StartupImpact.state(for: item, runningPIDs: pids) }
            return out
        }.value
    }

    func setDisabled(_ disabled: Bool, _ item: LaunchItem) async {
        if item.disableNeedsAdmin {
            guard let (script, prompt) = LaunchItemScanner.adminScript(for: .disable(disabled), item: item) else { return }
            do {
                try await PrivilegedShell.runAsAdmin(script, prompt: prompt)
            } catch let error as PrivilegedShell.AdminError {
                if !error.cancelled {
                    Log.error(.app, "couldn't \(disabled ? "disable" : "enable") login item \(item.plistPath.lastPathComponent)", error: error)
                }
                return
            } catch {
                Log.error(.app, "couldn't \(disabled ? "disable" : "enable") login item \(item.plistPath.lastPathComponent)", error: error)
                return
            }
        } else {
            await Task.detached { LaunchItemScanner.directDisable(disabled, item: item) }.value
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].disabled = disabled
        }
    }

    func remove(_ item: LaunchItem) async {
        let removed: Bool
        if item.removeNeedsAdmin {
            guard let (script, prompt) = LaunchItemScanner.adminScript(for: .remove, item: item) else { return }
            do {
                try await PrivilegedShell.runAsAdmin(script, prompt: prompt)
                removed = !FileManager.default.fileExists(atPath: item.plistPath.path)
            } catch let error as PrivilegedShell.AdminError {
                if !error.cancelled {
                    Log.error(.app, "couldn't remove login item \(item.plistPath.lastPathComponent)", error: error)
                }
                removed = false
            } catch {
                Log.error(.app, "couldn't remove login item \(item.plistPath.lastPathComponent)", error: error)
                removed = false
            }
        } else {
            removed = await Task.detached { LaunchItemScanner.trashUserAgent(item: item) }.value
        }
        if removed { items.removeAll { $0.id == item.id } }
    }
}
