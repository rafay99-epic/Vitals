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

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    init(model: VitalsModel, settings: AppSettings, fanControl: FanController) {
        self.model = model
        self.settings = settings
        self.fanControl = fanControl
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

        let label = MenuBarLabelView(onWidth: { [weak item] width in
            // Size the status item to the live content (the label is fixed-size,
            // so this fires only when the readout's width actually changes).
            item?.length = max(width.rounded(.up), 1)
        })
        .environmentObject(model)
        .environmentObject(settings)

        let host = MenuBarHostingView(rootView: AnyView(label))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        statusItem = item
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
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
