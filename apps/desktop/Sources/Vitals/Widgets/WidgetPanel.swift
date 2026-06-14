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
        // Dragging is driven by a SwiftUI gesture in `WidgetHost` (the AppKit
        // window-background drag doesn't fire reliably under the hosting view),
        // so leave this off to avoid two movers fighting.
        panel.isMovableByWindowBackground = false
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

        // Restore the saved frame (position *and* size) if we have one;
        // otherwise tuck it into the top-right, cascading so multiple widgets
        // don't stack on the exact same spot. We own this in UserDefaults rather
        // than via `setFrameAutosaveName`: the AppKit autosave restored position
        // but not size for these borderless panels, then re-saved the default
        // size on close — clobbering a resize.
        if let saved = savedFrame(for: kind) {
            panel.setFrame(saved, display: false)
        } else if let visible = NSScreen.main?.visibleFrame {
            let dy = CGFloat(index) * (size.height + 14)
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 22,
                y: visible.maxY - size.height - 22 - dy
            ))
        }
        return panel
    }

    /// UserDefaults key holding a widget's last `[x, y, width, height]`.
    static func frameKey(for kind: WidgetKind) -> String { "vitals.widget.frame.\(kind.rawValue)" }

    /// The persisted frame for a widget, clamped to its current size bounds, or
    /// nil if it has never been placed.
    private static func savedFrame(for kind: WidgetKind) -> CGRect? {
        guard let values = UserDefaults.standard.array(forKey: frameKey(for: kind)) as? [Double],
              values.count == 4 else { return nil }
        let width = min(max(CGFloat(values[2]), kind.minSize.width), kind.maxSize.width)
        let height = min(max(CGFloat(values[3]), kind.minSize.height), kind.maxSize.height)
        return CGRect(x: values[0], y: values[1], width: width, height: height)
    }
}
