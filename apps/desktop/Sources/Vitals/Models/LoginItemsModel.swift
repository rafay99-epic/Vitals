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
        await Task.detached { LaunchItemScanner.setDisabled(disabled, item: item) }.value
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].disabled = disabled
        }
    }
}
