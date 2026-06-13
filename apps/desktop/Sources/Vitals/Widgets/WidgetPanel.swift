import AppKit
import SwiftUI

/// Builds the floating `NSPanel` that hosts a widget: borderless, non-opaque,
/// drag-anywhere, never steals focus, shows on every Space. The SwiftUI content
/// gets the shared `VitalsModel` / `AppSettings` injected, so it ticks live.
@MainActor
enum WidgetPanel {
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
        panel.isFloatingPanel = true
        panel.level = onTop ? .floating : .normal
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

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
