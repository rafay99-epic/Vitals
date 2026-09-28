import SwiftUI

/// Every navigable destination, one flat tier in the sidebar: Overview, then
/// a read-only Monitor group and a write/maintenance Maintain group.
enum NavSection: String, CaseIterable, Identifiable {
    case overview
    case cpu, gpu, memory, battery, network, sensors, history
    case diskHealth, cleanup, applications
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:     return "Overview"
        case .cpu:          return "CPU"
        case .gpu:          return "GPU"
        case .memory:       return "Memory"
        case .battery:      return "Battery"
        case .network:      return "Network"
        case .sensors:      return "Temps & Fans"
        case .history:      return "History"
        case .diskHealth:   return "Disk Health"
        case .cleanup:      return "Cleanup"
        case .applications: return "Applications"
        case .settings:     return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview:     return "gauge.with.dots.needle.50percent"
        case .cpu:          return "cpu"
        case .gpu:          return "cpu.fill"
        case .memory:       return "memorychip"
        case .battery:      return "battery.100percent"
        case .network:      return "network"
        case .sensors:      return "thermometer.medium"
        case .history:      return "chart.xyaxis.line"
        case .diskHealth:   return "internaldrive"
        case .cleanup:      return "sparkles"
        case .applications: return "square.grid.2x2"
        case .settings:     return "gearshape"
        }
    }

}

/// The selected sidebar section, shared by the sidebar, the ⌘, command, and the
/// menu-bar panel. Settings is a section, so opening it means selecting `.settings`.
@MainActor
@Observable
final class Navigator {
    var section: NavSection = LaunchOverrides.section ?? .overview
}

/// Launch-argument deep links, e.g. `--section history --history-metric network`
/// (enum raw values). Used for Dev screenshot verification, since synthetic
/// keystrokes can land in the other Vitals when Stable and Dev run side by side.
enum LaunchOverrides {
    static var section: NavSection? {
        value(for: "--section").flatMap(NavSection.init(rawValue:))
    }

    static var historyMetric: HistoryView.Metric? {
        value(for: "--history-metric").flatMap(HistoryView.Metric.init(rawValue:))
    }

    /// The token following `flag`, or nil when the flag is absent or trailing.
    static func value(for flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
