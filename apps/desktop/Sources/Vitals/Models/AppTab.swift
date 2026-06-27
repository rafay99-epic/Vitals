import Foundation

/// The main window's five top-level destinations, in fixed order. A deliberately
/// small, curated set — Apple's own apps don't let you rearrange their tabs, and
/// the flexibility was the chaos. Each tab is a *job* or a *subsystem*, never a
/// single metric: the live readings that used to each own a tab (CPU, GPU,
/// Battery, Health, Disk, History, Processes) now live as segments inside
/// `System`, with the Dashboard as the glanceable overview above them.
///
/// Keyboard shortcuts are deliberately *not* a property here: they follow the
/// tab's position (⌘1 = leftmost), assigned in the header from `allCases` — so a
/// shortcut always matches what the eye sees.
enum AppTab: String, CaseIterable, Identifiable {
    case dashboard, system, storage, cleanup, applications
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:    return "Dashboard"
        case .system:       return "System"
        case .storage:      return "Storage"
        case .cleanup:      return "Cleanup"
        case .applications: return "Applications"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard:    return "gauge.with.dots.needle.50percent"
        case .system:       return "cpu"
        case .storage:      return "internaldrive"
        case .cleanup:      return "sparkles"
        case .applications: return "square.grid.2x2"
        }
    }
}
