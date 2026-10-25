import AppKit
import SwiftUI

/// Owns the status item and its `MenuBarPanel` popover. Keep the label static:
/// macOS re-snapshots a status item on the CPU for every frame it changes, so
/// any repeating animation burns CPU even with every window closed.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: VitalsModel
    private let settings: AppSettings
    private let navigator: Navigator
    private let share: ShareModel

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var picker: NSPopover?
    private var detached: NSPanel?
    private var launchObserver: NSObjectProtocol?
    private lazy var dropTarget = StatusDropTarget { [weak self] urls in self?.share.offer(urls, from: .menuBar) }

    init(model: VitalsModel, settings: AppSettings, navigator: Navigator, share: ShareModel) {
        self.model = model
        self.settings = settings
        self.navigator = navigator
        self.share = share
        super.init()

        share.presentPanel = { [weak self] in self?.showPanel(from: self?.visibleButton) }
        share.presentPicker = { [weak self] batch in self?.showPicker(batch) ?? false }

        observeChanges(of: { settings.showMenuBar }) { [weak self] in self?.setVisible($0) }
        // Install only after launch finishes: an NSStatusItem created while
        // NSApplicationMain is still registering gets a zero-height window.
        if NSApp?.isRunning == true {
            setVisible(settings.showMenuBar)
        } else {
            launchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.setVisible(self.settings.showMenuBar)
                    self.launchObserver.map(NotificationCenter.default.removeObserver)
                    self.launchObserver = nil
                }
            }
        }
    }

    private func setVisible(_ visible: Bool) {
        visible ? install() : remove()
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }
        button.target = self
        button.action = #selector(togglePopover)

        let label = MenuBarLabelView()
            .environment(model)
            .environment(settings)
            .environment(share)

        let host = MenuBarHostingView(rootView: AnyView(label))
        // The label's unconstrained ideal width, independent of the button's
        // current width, so a value that gains a digit can widen the item.
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        host.onIntrinsicSizeChange = { [weak self, weak item, weak host] in
            guard let self, let item, let host else { return }
            self.resize(item: item, toFit: host)
        }
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        statusItem = item
        resize(item: item, toFit: host)
        if let window = button.window {
            dropTarget.button = button
            window.registerForDraggedTypes([.fileURL])
            window.delegate = dropTarget
        }
        if LaunchOverrides.has("--menu-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showDetachedPanel() }
        }
    }

    private var visibleButton: NSStatusBarButton? {
        guard let button = statusItem?.button, let window = button.window, window.occlusionState.contains(.visible),
              NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: window.frame.midX, y: window.frame.midY)) })
        else { return nil }
        return button
    }

    private func panelView() -> some View {
        MenuBarPanel()
            .environment(model)
            .environment(settings)
            .environment(navigator)
            .environment(share)
    }

    private func showDetachedPanel() {
        let window = NSPanel(contentRect: .zero, styleMask: [.titled, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Menu bar panel"
        window.contentViewController = NSHostingController(rootView: panelView())
        window.isReleasedWhenClosed = false
        model.setMenuBarPanelVisible(true)
        share.panelOpen = true
        window.orderFrontRegardless()
        detached = window
    }

    /// Headroom so sub-pixel rounding on fractional-scaled displays can't shave
    /// the trailing glyph and trip a truncation ellipsis.
    private static let widthSlack: CGFloat = 2

    /// Deferred to the next runloop so it never resizes the button mid-layout.
    private func resize(item: NSStatusItem, toFit host: NSView) {
        DispatchQueue.main.async {
            let ideal = host.intrinsicContentSize.width
            guard ideal > 0 else { return }          // not laid out yet
            let target = (ideal + Self.widthSlack).rounded(.up)
            if abs(item.length - target) > 0.5 { item.length = target }
        }
    }

    private func remove() {
        popover?.performClose(nil)
        popover = nil
        picker?.performClose(nil)
        picker = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        showPanel(from: statusItem?.button)
    }

    private func showPanel(from button: NSStatusBarButton?) {
        guard let button else { return }
        picker?.performClose(nil)
        if let popover, popover.isShown { return }
        let popover = NSPopover()
        popover.behavior = .transient // dismiss on click outside / Esc
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: panelView())
        self.popover = popover
        button.highlight(true)
        model.setMenuBarPanelVisible(true)
        share.panelOpen = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showPicker(_ batch: ShareModel.Batch) -> Bool {
        guard let button = visibleButton else { return false }
        popover?.performClose(nil)
        picker?.performClose(nil)
        let picker = NSPopover()
        picker.behavior = .transient
        picker.delegate = self
        let close: () -> Void = { [weak picker] in picker?.performClose(nil) }
        let view = PhonePicker(batch: batch, selection: share.defaultTargets, onSend: { [weak share] ids in
            close()
            share?.pick(batch, to: ids, from: .menuBar)
        }, onCancel: close)
            .environment(share)
        picker.contentViewController = NSHostingController(rootView: view)
        self.picker = picker
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        if let closed = notification.object as? NSPopover, closed === picker {
            picker = nil
            return
        }
        model.setMenuBarPanelVisible(false)
        share.panelOpen = false
        statusItem?.button?.highlight(false)
        popover = nil
    }
}

/// Returns nil from `hitTest` so clicks fall through to the status-item button.
final class MenuBarHostingView: NSHostingView<AnyView> {
    /// Fires when the label's ideal size changes so the item can re-fit.
    var onIntrinsicSizeChange: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }

    required init(rootView: AnyView) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

@MainActor
final class StatusDropTarget: NSObject, NSWindowDelegate, NSDraggingDestination {
    weak var button: NSStatusBarButton?
    private let onDrop: ([URL]) -> Void

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !DropFiles.fileURLs(from: sender.draggingPasteboard).isEmpty else { return [] }
        button?.highlight(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        DropFiles.fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.highlight(false)
        let urls = DropFiles.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}

@MainActor
final class ShareServices: NSObject {
    private let share: ShareModel

    init(share: ShareModel) {
        self.share = share
    }

    @objc func sendToPhone(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        let urls = DropFiles.fileURLs(from: pboard)
        guard !urls.isEmpty else {
            error?.pointee = "Choose files or folders to send."
            return
        }
        share.offer(urls, from: .finder)
    }
}

/// Keeps the app alive when all windows are closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var openFiles: (([URL]) -> Void)? {
        didSet { if let openFiles, !pendingFiles.isEmpty { openFiles(pendingFiles); pendingFiles = [] } }
    }
    @MainActor private static var pendingFiles: [URL] = []
    @MainActor static var services: NSObject? {
        didSet { if NSApp?.isRunning == true { registerServices() } }
    }

    @MainActor private static func registerServices() {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.registerServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        if let open = Self.openFiles { open(files) } else { Self.pendingFiles += files }
    }

    /// Records a clean shutdown so the next launch can tell a graceful quit from
    /// a crash or a kill (see `CrashReporter`).
    func applicationWillTerminate(_ notification: Notification) {
        CrashReporter.markCleanShutdown()
    }
}
