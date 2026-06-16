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

    var userItems: [LaunchItem] { items.filter { $0.kind == .userAgent } }
    var systemItems: [LaunchItem] { items.filter { $0.kind != .userAgent } }

    func loadIfNeeded() async {
        guard !loaded, !loading else { return }
        await reload()
    }

    func reload() async {
        loading = true
        items = await Task.detached { LaunchItemScanner.scan() }.value
        loading = false
        loaded = true
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
