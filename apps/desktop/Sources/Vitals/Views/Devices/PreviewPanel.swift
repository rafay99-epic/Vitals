import AppKit
import Quartz
import SwiftUI

/// Shows Mac copies of phone files in the system Quick Look panel. It joins the main window's
/// responder chain, which is where the panel looks for whoever feeds it, as Finder does.
@MainActor
final class PreviewPanel: NSResponder, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    static let shared = PreviewPanel()

    private var urls: [URL] = []
    private var closed: (() -> Void)?

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    /// Opens the panel on `urls`. `closed` runs when the person closes it.
    func show(_ urls: [URL], closed: @escaping () -> Void) {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let panel = QLPreviewPanel.shared()
        else { return }
        if window.nextResponder !== self {
            nextResponder = window.nextResponder
            window.nextResponder = self
        }
        self.urls = urls
        self.closed = closed
        panel.updateController()
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    /// Adds one more file to the open panel; the arrow keys reach it.
    func append(_ url: URL) {
        urls.append(url)
        if isVisible { QLPreviewPanel.shared().reloadData() }
    }

    /// Closes the panel, as Space or Escape would.
    func dismiss() {
        if isVisible { QLPreviewPanel.shared().orderOut(nil) }
    }

    /// Closes the panel without telling whoever opened it, for a new preview taking its place.
    func close() {
        closed = nil
        dismiss()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { !urls.isEmpty }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        guard !panel.isVisible else { return }
        let closed = closed
        self.closed = nil
        closed?()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }

    /// Arrow keys step through several files.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, urls.count > 1 else { return false }
        let step: Int
        switch event.specialKey {
        case .leftArrow?, .upArrow?: step = -1
        case .rightArrow?, .downArrow?: step = 1
        default: return false
        }
        panel.currentPreviewItemIndex = (panel.currentPreviewItemIndex + step + urls.count) % urls.count
        return true
    }
}

extension View {
    /// Space opens Quick Look on the selection like Finder while this view is on screen, and
    /// closes it again. `action` returns false when there's nothing to preview, so the key goes on.
    func spaceToPreview(_ action: @escaping () -> Bool) -> some View {
        modifier(SpaceToPreview(action: action))
    }
}

private struct SpaceToPreview: ViewModifier {
    let action: () -> Bool
    @State private var monitor = SpaceMonitor()

    func body(content: Content) -> some View {
        monitor.action = action
        return content
            .onAppear { monitor.start() }
            .onDisappear { monitor.stop() }
    }
}

@MainActor
private final class SpaceMonitor {
    var action: () -> Bool = { false }
    private var token: Any?

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49, !event.isARepeat,
                  event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
            else { return event }
            if PreviewPanel.shared.isVisible {
                PreviewPanel.shared.dismiss()
                return nil
            }
            guard event.window?.isMainWindow == true, !(event.window?.firstResponder is NSText) else { return event }
            return self.action() ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
