import Foundation

/// The main window's top-level destinations. Lives in the model layer rather
/// than inside the view so settings can reorder, hide, size and re-style the
/// navigation bar without the view owning that state.
///
/// Keyboard shortcuts are deliberately *not* a property here: they follow the
/// tab's visible position (⌘1 = leftmost), assigned in the header from the
/// ordered, unhidden list — so a shortcut always matches what the eye sees.
enum AppTab: String, CaseIterable, Identifiable {
    case dashboard, gpu, battery, health, history, processes, applications, loginItems, cleanup, storage
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        case .health: return "Health"
        case .history: return "History"
        case .processes: return "Processes"
        case .applications: return "Applications"
        case .loginItems: return "Login Items"
        case .cleanup: return "Cleanup"
        case .storage: return "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .gpu: return "cpu.fill"
        case .battery: return "battery.100percent"
        case .health: return "waveform.path.ecg"
        case .history: return "chart.xyaxis.line"
        case .processes: return "list.bullet"
        case .applications: return "square.grid.2x2"
        case .loginItems: return "power"
        case .cleanup: return "sparkles"
        case .storage: return "internaldrive"
        }
    }

    /// The Dashboard is the app's home and can never be hidden — it guarantees
    /// the window always has somewhere to land.
    var canHide: Bool { self != .dashboard }

    // MARK: Default navigation

    /// What the nav bar shows on a fresh install: a deliberately small,
    /// monitoring-first set. Vitals' soul is a hardware monitor, so the default
    /// foregrounds the live vitals (Dashboard), what's driving them (Processes),
    /// their trend (History), battery health, and disk — five items, like
    /// Activity Monitor. Following Hick's law and progressive disclosure, the
    /// deep-dive and management tabs start hidden and are one switch away in
    /// Settings → Tabs.
    static let defaultVisible: [AppTab] = [.dashboard, .processes, .history, .battery, .storage]

    /// The full default order: the visible set first, then the hidden tabs
    /// grouped by concern — monitoring deep-dives (GPU, Health), then the
    /// management tools (Applications, Login Items, Cleanup). Contains every tab,
    /// so a fresh install starts from a complete, intentional order.
    static let defaultOrder: [AppTab] = [
        .dashboard, .processes, .history, .battery, .storage,   // shown
        .gpu, .health,                                          // monitoring deep-dives
        .applications, .loginItems, .cleanup,                   // management tools
    ]

    /// Hidden on a fresh install — everything not in `defaultVisible`, in
    /// `defaultOrder` order.
    static var defaultHidden: [AppTab] { defaultOrder.filter { !defaultVisible.contains($0) } }
}
