import AppKit
import SwiftUI

/// Surfaces the hosting `NSWindow` up to SwiftUI so gestures can move and resize
/// the actual panel. Embedding AppKit click targets *inside* the hosting view
/// doesn't receive mouse events in a non-activating panel (clicks fall through
/// to the desktop), but SwiftUI's own gestures do — they just need a handle on
/// the window to drive. This invisible probe provides it.
struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onResolve(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in onResolve(nsView?.window) }
    }
}
