import AppKit
import SwiftUI

/// Owns the floating desktop widget panels and which ones are shown. It holds
/// the *shared* `VitalsModel` / `AppSettings`, so every widget renders the same
/// live data as the app — no separate polling. Visible widgets and the
/// "keep on top" preference persist; each panel's position persists via its
/// frame autosave name.
@MainActor
final class WidgetManager: ObservableObject {
    @Published private(set) var visible: Set<WidgetKind> = []
    /// Off by default: widgets sit on the desktop, behind your windows. On:
    /// they float above everything.
    @Published var onTop: Bool {
        didSet {
            let level = WidgetPanel.windowLevel(onTop: onTop)
            for panel in panels.values {
                panel.isFloatingPanel = onTop
                panel.level = level
                // Re-order so the new level takes effect immediately — changing
                // `.level` on a visible window doesn't restack until it's ordered
                // (this is why the toggle used to need an app restart).
                // orderFrontRegardless respects the level, so when off it still
                // settles onto the desktop layer rather than over your windows.
                panel.orderFrontRegardless()
            }
            defaults.set(onTop, forKey: Keys.onTop)
        }
    }

    private let model: VitalsModel
    private let settings: AppSettings
    private var panels: [WidgetKind: NSPanel] = [:]
    private let defaults = UserDefaults.standard
    private var realignWork: DispatchWorkItem?

    private enum Keys {
        static let visible = "widgets.visible"
        static let onTop = "widgets.onTop"
    }

    init(model: VitalsModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        self.onTop = defaults.object(forKey: Keys.onTop) as? Bool ?? false

        // Reopen last session's widgets once the run loop is up (NSApp must be
        // alive before panels can order front).
        let restored = ((defaults.array(forKey: Keys.visible) as? [String]) ?? [])
            .compactMap(WidgetKind.init(rawValue:))
        DispatchQueue.main.async { [weak self] in
            restored.forEach { self?.show($0) }
        }

        // Displays come and go; `.stationary` panels are never rescued by the
        // system, so a widget on an unplugged monitor stays stranded off-screen
        // (invisible and unreachable) until we move it back ourselves.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        realignWork?.cancel()
    }

    /// A display configuration change fires this several times in a burst —
    /// debounce, then realign once the layout has settled.
    @objc private func screensChanged() {
        realignWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.realignPanels() }
        realignWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Puts every widget back where it belongs after a display change. A panel
    /// whose saved spot exists again returns to it; a panel left stranded
    /// off-screen is re-tucked into the default cascade. The saved spot is
    /// never overwritten here (only a user drag persists), so unplugging and
    /// replugging a monitor round-trips every widget to where the user put it.
    private func realignPanels() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard !screens.isEmpty else { return }
        var rescued = 0
        for (kind, panel) in panels.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if let saved = WidgetPanel.savedFrame(for: kind),
               WidgetPlacement.fitted(saved, within: screens) == saved {
                if panel.frame != saved { panel.setFrame(saved, display: true) }
                continue
            }
            if WidgetPlacement.fitted(panel.frame, within: screens) != panel.frame {
                let spot = WidgetPanel.cascadeFrame(size: panel.frame.size, index: rescued)
                    ?? WidgetPlacement.fitted(panel.frame, within: screens)
                panel.setFrame(spot, display: true)
                rescued += 1
            }
        }
    }

    func isVisible(_ kind: WidgetKind) -> Bool { visible.contains(kind) }

    func toggle(_ kind: WidgetKind) {
        isVisible(kind) ? hide(kind) : show(kind)
    }

    func show(_ kind: WidgetKind) {
        guard panels[kind] == nil else { return }
        let panel = WidgetPanel.make(
            kind: kind,
            onTop: onTop,
            index: panels.count,
            model: model,
            settings: settings,
            onClose: { [weak self] in self?.hide(kind) }
        )
        panels[kind] = panel
        panel.orderFrontRegardless()
        visible.insert(kind)
        persistVisible()
        syncGPUSampling()
    }

    func hide(_ kind: WidgetKind) {
        panels[kind]?.orderOut(nil)
        panels[kind] = nil
        visible.remove(kind)
        persistVisible()
        syncGPUSampling()
    }

    private func persistVisible() {
        defaults.set(visible.map(\.rawValue), forKey: Keys.visible)
    }

    /// Tells the model whether any GPU-bearing widget (`.gpu` or `.combined`) is
    /// on screen, so the IOReport GPU sample is only skipped when nothing visible
    /// reads it — a shown widget must never go stale.
    private func syncGPUSampling() {
        model.setGPUWidgetVisible(visible.contains(.gpu) || visible.contains(.combined))
    }
}
