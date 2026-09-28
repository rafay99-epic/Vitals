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

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var launchObserver: NSObjectProtocol?

    init(model: VitalsModel, settings: AppSettings, navigator: Navigator) {
        self.model = model
        self.settings = settings
        self.navigator = navigator
        super.init()

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
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let panel = MenuBarPanel()
            .environment(model)
            .environment(settings)
            .environment(navigator)

        let popover = NSPopover()
        popover.behavior = .transient // dismiss on click outside / Esc
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: panel)
        self.popover = popover
        button.highlight(true)
        model.setMenuBarPanelVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setMenuBarPanelVisible(false)
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

/// Keeps the app alive when all windows are closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Records a clean shutdown so the next launch can tell a graceful quit from
    /// a crash or a kill (see `CrashReporter`).
    func applicationWillTerminate(_ notification: Notification) {
        CrashReporter.markCleanShutdown()
    }
}
