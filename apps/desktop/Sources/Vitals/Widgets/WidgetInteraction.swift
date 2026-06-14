import AppKit
import SwiftUI

/// Makes a widget draggable from anywhere on its body. SwiftUI's
/// `isMovableByWindowBackground` doesn't fire reliably when a hosting view
/// covers the window, and at the desktop window level there's no title bar to
/// grab — so we drive an explicit AppKit window drag, which also stays smooth
/// (a SwiftUI `DragGesture` jitters because the content moves under the cursor).
/// Right-click offers Close, replacing the context menu the card can no longer
/// show (its content is hit-test-disabled so drags fall through to here).
struct WidgetDragSurface: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.onClose = onClose
    }

    final class DragView: NSView {
        var onClose: (() -> Void)?

        // Start a drag on the very first click, without first activating the app
        // — these are non-activating panels.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)   // runs the drag loop to mouse-up
            saveFrame()
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Close Widget", action: #selector(closeWidget), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return menu
        }

        @objc private func closeWidget() { onClose?() }

        private func saveFrame() {
            guard let window, !window.frameAutosaveName.isEmpty else { return }
            window.saveFrame(usingName: window.frameAutosaveName)
        }
    }
}

/// A corner grip that resizes the widget's panel, anchored at its top-left so it
/// grows down-and-right (the corner under the cursor). Clamped to the kind's
/// min/max so a panel can't collapse or balloon, and the new size persists.
struct WidgetResizeGrip: NSViewRepresentable {
    let minSize: CGSize
    let maxSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = ResizeView()
        view.minSize = minSize
        view.maxSize = maxSize
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ResizeView else { return }
        view.minSize = minSize
        view.maxSize = maxSize
    }

    final class ResizeView: NSView {
        var minSize: CGSize = .zero
        var maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        private var startFrame: NSRect = .zero
        private var startMouse: NSPoint = .zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // Track in screen coordinates so the moving window can't feed back
            // into the delta.
            startFrame = window.frame
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let width = clamp(startFrame.width + (now.x - startMouse.x), minSize.width, maxSize.width)
            let height = clamp(startFrame.height - (now.y - startMouse.y), minSize.height, maxSize.height)
            // Pin the top-left corner: AppKit origin is bottom-left, so as height
            // changes we move y to keep the top edge fixed.
            let top = startFrame.maxY
            window.setFrame(NSRect(x: startFrame.minX, y: top - height, width: width, height: height),
                            display: true)
        }

        override func mouseUp(with event: NSEvent) {
            guard let window, !window.frameAutosaveName.isEmpty else { return }
            window.saveFrame(usingName: window.frameAutosaveName)
        }

        private func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            min(max(value, lo), hi)
        }
    }
}
