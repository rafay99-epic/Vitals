import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and its dropdown, replacing SwiftUI's
/// `MenuBarExtra`. The reason for going manual: MenuBarExtra can only show a
/// rasterized image for a multi-metric label, so animation means re-rendering
/// frames on the CPU — which can't do a cheap 120 Hz. A custom status item hosts
/// the label as a **live** view (`MenuBarLabelView`), so its animation runs on
/// the Core Animation compositor at the display's refresh rate (ProMotion
/// included) with no per-frame CPU. The dropdown is a transient `NSPopover`
/// hosting the same `MenuBarPanel`.
@MainActor
final class MenuBarController: NSObject, ObservableObject, NSPopoverDelegate {
    private let model: VitalsModel
    private let settings: AppSettings
    private let fanControl: FanController
    private let navigator: Navigator

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    init(model: VitalsModel, settings: AppSettings, fanControl: FanController, navigator: Navigator) {
        self.model = model
        self.settings = settings
        self.fanControl = fanControl
        self.navigator = navigator
        super.init()

        // Show/hide with the preference.
        settings.$showMenuBar
            .removeDuplicates()
            .sink { [weak self] show in self?.setVisible(show) }
            .store(in: &cancellables)
        // Defer the first build until the run loop is up — a status item can't
        // be created before NSApp exists (mirrors WidgetManager).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setVisible(self.settings.showMenuBar)
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
        // Report a real intrinsic size so `intrinsicContentSize` reflects the
        // label's ideal width — the *unconstrained* footprint, independent of the
        // button's current width. That independence is the whole point: the old
        // GeometryReader measured a width the button width already clamped, so a
        // value that grew a digit ("4%" → "47%") could never widen the item back
        // and the row truncated to "4…" permanently (issues #45, #50).
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

    /// Size the status item to the label's ideal width, read off the hosting
    /// view's `intrinsicContentSize`. Deferred to the next runloop so it reads the
    /// post-update layout and never resizes the button mid-layout pass; guarded so
    /// an unchanged width doesn't churn the status bar.
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
            .environmentObject(fanControl)
            .environmentObject(navigator)
            .environment(\.animationsEnabled, settings.animationsEnabled)

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
    /// Fires whenever the live label's ideal size changes (a value gains or loses
    /// a digit, or the chosen metrics change) so the controller can re-fit the
    /// status item to the new intrinsic width.
    var onIntrinsicSizeChange: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }

    required init(rootView: AnyView) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

/// Keeps the app alive when its windows are all closed — the menu-bar item is
/// the app's home, like any menu-bar utility. (MenuBarExtra used to provide this
/// implicitly.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Records a clean shutdown so the next launch can tell a graceful quit from
    /// a crash or a kill (see `CrashReporter`).
    func applicationWillTerminate(_ notification: Notification) {
        CrashReporter.markCleanShutdown()
    }
}
