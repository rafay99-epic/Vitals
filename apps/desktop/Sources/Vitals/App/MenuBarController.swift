import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and its dropdown (a transient `NSPopover`
/// hosting `MenuBarPanel`). The label is a hosted SwiftUI view, so its width
/// follows the readings. Keep it static: macOS re-snapshots a status item on the
/// CPU for every frame it changes, so any repeating animation here burns CPU
/// continuously, even with every window closed.
@MainActor
final class MenuBarController: NSObject, ObservableObject, NSPopoverDelegate {
    private let model: VitalsModel
    private let settings: AppSettings
    private let navigator: Navigator

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    init(model: VitalsModel, settings: AppSettings, navigator: Navigator) {
        self.model = model
        self.settings = settings
        self.navigator = navigator
        super.init()

        // Show/hide with the preference. `dropFirst`: @Published replays the
        // current value at subscribe, which would install mid `App.init`.
        settings.$showMenuBar
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] show in self?.setVisible(show) }
            .store(in: &cancellables)
        // Install only after launch finishes: an NSStatusItem created while
        // NSApplicationMain is still registering gets a zero-height window.
        if NSApp?.isRunning == true {
            setVisible(settings.showMenuBar)
        } else {
            NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
                .prefix(1)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.setVisible(self.settings.showMenuBar)
                }
                .store(in: &cancellables)
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
            .environmentObject(model)
            .environmentObject(settings)

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

    /// Slack (pt) added on top of the label's ideal width. Sub-pixel rounding on
    /// fractional-scaled displays ("More Space", external monitors) can otherwise
    /// shave the trailing glyph by a pixel and trip a truncation ellipsis; a
    /// couple of points of headroom makes the readout scale-independent.
    private static let widthSlack: CGFloat = 2

    /// Size the status item to the label's ideal width. Deferred to the next
    /// runloop so it never resizes the button mid-layout; unchanged widths skip.
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
            .environmentObject(model)
            .environmentObject(settings)
            .environmentObject(navigator)

        let popover = NSPopover()
        popover.behavior = .transient // dismiss on click outside / Esc
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: panel)
        self.popover = popover
        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        popover = nil
    }
}

/// The status item's hosted label. Returns nil from `hitTest` so clicks fall
/// through to the status-item button (the label is display-only) and toggle the
/// dropdown.
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

/// Keeps the app alive when its windows are all closed; the menu-bar item is
/// the app's home.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Records a clean shutdown so the next launch can tell a graceful quit from
    /// a crash or a kill (see `CrashReporter`).
    func applicationWillTerminate(_ notification: Notification) {
        CrashReporter.markCleanShutdown()
    }
}
