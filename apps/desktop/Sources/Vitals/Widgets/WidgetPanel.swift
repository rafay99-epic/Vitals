import AppKit
import SwiftUI

/// Builds the floating `NSPanel` that hosts a widget: borderless, non-opaque,
/// drag-anywhere, never steals focus, shows on every Space. The SwiftUI content
/// gets the shared `VitalsModel` / `AppSettings` injected, so it ticks live.
@MainActor
enum WidgetPanel {
    /// Where a widget sits in the window stack. "Desktop" pins it to the real
    /// desktop layer (just above the wallpaper, below icons and every app
    /// window) so it composites *with* the desktop during a Space switch and
    /// never pops above your windows. A level just below normal (e.g. -1) is
    /// treated like an ordinary window mid-transition and flickers to the front
    /// — the desktop layer doesn't. "Float" keeps it above everything.
    static func windowLevel(onTop: Bool) -> NSWindow.Level {
        onTop
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    static func make(
        kind: WidgetKind,
        onTop: Bool,
        index: Int,
        model: VitalsModel,
        settings: AppSettings,
        onClose: @escaping () -> Void
    ) -> NSPanel {
        let size = kind.defaultSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = onTop
        panel.level = windowLevel(onTop: onTop)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = kind.minSize
        panel.maxSize = kind.maxSize
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        // No appearance animation: the utility-window fade re-fires during a
        // Space switch and reads as a flicker / the widget "reappearing".
        panel.animationBehavior = .none
        // Pinned to every Space and stationary, so a Space switch never moves,
        // hides, or re-shows it. (No .fullScreenAuxiliary — a desktop widget
        // shouldn't ride over full-screen apps.)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let host = NSHostingView(
            rootView: WidgetHost(kind: kind, onClose: onClose)
                .environmentObject(model)
                .environmentObject(settings)
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        // Restore the saved position; otherwise tuck it into the top-right,
        // cascading so multiple widgets don't stack on the exact same spot.
        let name = "vitals.widget.\(kind.rawValue)"
        if !panel.setFrameUsingName(name) {
            if let visible = NSScreen.main?.visibleFrame {
                let dy = CGFloat(index) * (size.height + 14)
                panel.setFrameOrigin(NSPoint(
                    x: visible.maxX - size.width - 22,
                    y: visible.maxY - size.height - 22 - dy
                ))
            }
        }
        panel.setFrameAutosaveName(name)
        return panel
    }
}
