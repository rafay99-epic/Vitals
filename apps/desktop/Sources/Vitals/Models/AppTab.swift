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
}
