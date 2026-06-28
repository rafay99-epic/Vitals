import SwiftUI

/// The app-wide selected destination — one source of truth so every surface that
/// can change what the main window shows drives the *same* selection: the
/// sidebar rows, the ⌘, command, the menu-bar panel's gear, and the Processes
/// empty-state "Open Settings". Settings now lives inside the window as the last
/// sidebar section (`.settings`), not a separate dialog, so "open settings" is
/// just "select that section" — set `section` and bring the main window forward.
@MainActor
final class Navigator: ObservableObject {
    @Published var section: NavSection = .overview
}
