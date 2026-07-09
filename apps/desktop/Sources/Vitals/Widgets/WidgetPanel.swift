import AppKit
import SwiftUI

/// Builds the floating `NSPanel` that hosts a widget: borderless, non-opaque,
/// drag-anywhere, never steals focus, shows on every Space. The SwiftUI content
/// gets the shared `VitalsModel` / `AppSettings` injected, so it ticks live.
/// Placement is the `WidgetManager`'s job (it knows the per-arrangement saved
/// frames); this file only knows how to build a panel and stack it.
@MainActor
enum WidgetPanel {
    /// Where a widget sits in the window stack for a mode. "On desktop" pins
    /// it just *above* Finder's full-screen desktop-icons window — below every
    /// app window — so it composites *with* the desktop during a Space switch
    /// and never pops above your windows; being above the icons window is what
    /// keeps it clickable (that window covers the whole screen and swallows
    /// every mouse event). "Behind icons" drops *below* the icons window, onto
    /// the wallpaper layer — desktop files always render on top — which also
    /// means the icons window would swallow every click, so that mode is
    /// paired with `ignoresMouseEvents` and surfaces to the interactive
    /// desktop level only while Vitals is the active app (that's how the user
    /// arranges them). A level just below normal (e.g. -1) is not an option —
    /// it's treated like an ordinary window mid-Space-transition and flickers
    /// to the front; the desktop layers don't.
    static func windowLevel(mode: WidgetLevelMode, appActive: Bool) -> NSWindow.Level {
        switch mode {
        case .floating:
            return .floating
        case .desktop:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .behindIcons:
            return appActive
                ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        }
    }

    /// Applies a mode to a live panel. Re-orders afterwards because changing
    /// `.level` on a visible window doesn't restack until it's ordered (this
    /// is why the old on-top toggle needed an app restart);
    /// `orderFrontRegardless` respects the level, so a desktop-layer panel
    /// still settles onto the desktop rather than over your windows.
    static func apply(mode: WidgetLevelMode, appActive: Bool, to panel: NSPanel) {
        panel.isFloatingPanel = mode == .floating
        panel.level = windowLevel(mode: mode, appActive: appActive)
        // Behind the icons the panel can't receive clicks anyway (the icons
        // window swallows them) — declaring it click-through keeps the whole
        // stack honest and cheap.
        panel.ignoresMouseEvents = mode == .behindIcons && !appActive
        panel.orderFrontRegardless()
    }

    /// What a widget panel is and where it belongs, resolved by the manager:
    /// identity, stacking mode + current app activity, and the frame it should
    /// restore to (nil → the default cascade spot for `cascadeIndex`).
    struct Spec {
        let kind: WidgetKind
        let mode: WidgetLevelMode
        let appActive: Bool
        let frame: CGRect?
        let cascadeIndex: Int
    }

    static func make(
        _ spec: Spec,
        model: VitalsModel,
        settings: AppSettings,
        onClose: @escaping () -> Void,
        onFrameChanged: @escaping (CGRect) -> Void
    ) -> NSPanel {
        let kind = spec.kind
        let size = spec.frame?.size ?? kind.defaultSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
            rootView: WidgetHost(kind: kind, onClose: onClose, onFrameChanged: onFrameChanged)
                .environmentObject(model)
                .environmentObject(settings)
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        // The manager resolved where this widget belongs (its spot in the
        // current display arrangement, migrated or legacy). No resolved spot —
        // a widget never placed anywhere — tucks into the main screen's
        // top-right, cascading so multiple new widgets don't stack.
        if let spot = spec.frame ?? cascadeFrame(size: size, index: spec.cascadeIndex) {
            panel.setFrame(spot, display: false)
        }
        // Level + ordering last, so the panel first appears at its real spot.
        apply(mode: spec.mode, appActive: spec.appActive, to: panel)
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
}
