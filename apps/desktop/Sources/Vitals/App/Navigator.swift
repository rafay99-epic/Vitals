import SwiftUI

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
