import SwiftUI

/// The app-wide selected destination — one source of truth so every surface that
/// can change what the main window shows drives the *same* selection: the
/// sidebar rows, the ⌘, command, the menu-bar panel's gear, and the Processes
/// empty-state "Open Settings". Settings now lives inside the window as the last
/// sidebar section (`.settings`), not a separate dialog, so "open settings" is
/// just "select that section" — set `section` and bring the main window forward.
@MainActor
final class Navigator: ObservableObject {
    @Published var section: NavSection = LaunchOverrides.section ?? .overview
}

/// Optional launch-argument deep links: `--section <id>` opens the window on
/// that sidebar section, and `--history-metric <id>` preselects the History
/// tab's metric (ids are the enums' raw values, e.g. `--section history
/// --history-metric network`). These exist so a script can open a build
/// directly onto a specific surface — Dev-build screenshot verification runs
/// this way because synthetic keystrokes can land in the *other* Vitals when
/// Stable and Dev run side by side. Absent or invalid values change nothing.
enum LaunchOverrides {
    static var section: NavSection? {
        value(for: "--section").flatMap(NavSection.init(rawValue:))
    }

    static var historyMetric: HistoryView.Metric? {
        value(for: "--history-metric").flatMap(HistoryView.Metric.init(rawValue:))
    }

    /// The token following `flag`, or nil when the flag is absent or trailing.
    /// `args` is injectable for tests; callers use the process's real arguments.
    static func value(for flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
