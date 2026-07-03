import AppKit
import SwiftUI

/// Builds the floating `NSPanel` that hosts a widget: borderless, non-opaque,
/// drag-anywhere, never steals focus, shows on every Space. The SwiftUI content
/// gets the shared `VitalsModel` / `AppSettings` injected, so it ticks live.
@MainActor
enum WidgetPanel {
    /// Where a widget sits in the window stack. "Desktop" pins it to the
    /// desktop layer — just *above* Finder's full-screen desktop-icons window,
    /// below every app window — so it composites *with* the desktop during a
    /// Space switch and never pops above your windows. It must sit above the
    /// icons window: that window covers the whole screen and swallows every
    /// mouse event, so a panel below it (the old `.desktopWindow + 1`) can
    /// never be clicked, dragged, or resized. A level just below normal (e.g.
    /// -1) is also wrong — it's treated like an ordinary window mid-transition
    /// and flickers to the front; the desktop layers don't. "Float" keeps the
    /// widget above everything.
    static func windowLevel(onTop: Bool) -> NSWindow.Level {
        onTop
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
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

        // Restore the saved frame (position *and* size) if we have one —
        // nudged fully on-screen if a display change left it poking past an
        // edge, so a Dock or resolution tweak never costs the user their spot.
        // Only a frame stranded on a vanished display (invisible and
        // unreachable) — or a widget never placed — tucks into the top-right,
        // cascading so multiple widgets don't stack on the exact same spot.
        // We own this in UserDefaults rather than via `setFrameAutosaveName`:
        // the AppKit autosave restored position but not size for these
        // borderless panels, then re-saved the default size on close —
        // clobbering a resize.
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let saved = savedFrame(for: kind),
           let spot = WidgetPlacement.rescued(saved, within: screens) {
            panel.setFrame(spot, display: false)
        } else {
            let size = savedFrame(for: kind)?.size ?? size
            if let cascade = cascadeFrame(size: size, index: index) {
                panel.setFrame(cascade, display: false)
            }
        }
        return panel
    }

    /// The default spot for the `index`-th widget: tucked into the main
    /// screen's top-right, cascading downward so widgets don't stack.
    static func cascadeFrame(size: CGSize, index: Int) -> CGRect? {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return nil }
        let dy = CGFloat(index) * (size.height + 14)
        return CGRect(
            x: visible.maxX - size.width - 22,
            y: visible.maxY - size.height - 22 - dy,
            width: size.width, height: size.height
        )
    }

    /// UserDefaults key holding a widget's last `[x, y, width, height]`.
    static func frameKey(for kind: WidgetKind) -> String { "vitals.widget.frame.\(kind.rawValue)" }

    /// The persisted frame for a widget, clamped to its current size bounds, or
    /// nil if it has never been placed.
    static func savedFrame(for kind: WidgetKind) -> CGRect? {
        guard let values = UserDefaults.standard.array(forKey: frameKey(for: kind)) as? [Double],
              values.count == 4 else { return nil }
        let width = min(max(CGFloat(values[2]), kind.minSize.width), kind.maxSize.width)
        let height = min(max(CGFloat(values[3]), kind.minSize.height), kind.maxSize.height)
        return CGRect(x: values[0], y: values[1], width: width, height: height)
    }
}
