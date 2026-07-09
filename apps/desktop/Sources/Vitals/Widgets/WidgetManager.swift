import AppKit
import SwiftUI

/// Owns the floating desktop widget panels and which ones are shown. It holds
/// the *shared* `VitalsModel` / `AppSettings`, so every widget renders the same
/// live data as the app — no separate polling. Visible widgets and the
/// placement mode persist; each panel's frame persists **per display
/// arrangement** (`WidgetFrameStore`), so the docked layout and the
/// laptop-open layout are separate memories that restore exactly.
@MainActor
final class WidgetManager: ObservableObject {
    @Published private(set) var visible: Set<WidgetKind> = []

    /// Where widgets sit in the window stack (above windows / on the desktop /
    /// behind the desktop icons). Persists; applies live to every open panel.
    @Published var levelMode: WidgetLevelMode {
        didSet {
            defaults.set(levelMode.rawValue, forKey: Keys.level)
            applyLevels()
        }
    }

    private let model: VitalsModel
    private let settings: AppSettings
    private var panels: [WidgetKind: NSPanel] = [:]
    private let defaults = UserDefaults.standard
    private let frameStore = WidgetFrameStore(defaults: .standard)
    private var realignWork: DispatchWorkItem?
    /// The visible frames of the arrangement the panels are currently laid
    /// out for — the migration source when a never-seen arrangement appears.
    private var lastScreens: [CGRect] = NSScreen.screens.map(\.visibleFrame)

    private enum Keys {
        static let visible = "widgets.visible"
        static let onTop = "widgets.onTop" // legacy Bool, migrated into `level`
        static let level = "widgets.level"
    }

    init(model: VitalsModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        // Migrate the old on-top switch into the three-way mode once; a user
        // who had widgets floating keeps them floating.
        if let stored = defaults.string(forKey: Keys.level),
           let mode = WidgetLevelMode(rawValue: stored) {
            self.levelMode = mode
        } else {
            self.levelMode = (defaults.object(forKey: Keys.onTop) as? Bool ?? false) ? .floating : .desktop
        }

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
        // Behind-icons widgets surface while Vitals is the active app (that's
        // how the user arranges them) and sink back when it isn't.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appActivityChanged),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appActivityChanged),
            name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        realignWork?.cancel()
    }

    // MARK: - Display arrangements

    /// Identity of the current display arrangement (see `WidgetFrameStore`).
    private var arrangementKey: String {
        WidgetFrameStore.arrangementKey(for: NSScreen.screens.map(\.frame))
    }

    /// A display configuration change fires this several times in a burst —
    /// debounce, then realign once the layout has settled.
    @objc private func screensChanged() {
        realignWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.realignPanels() }
        realignWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Puts every widget where it belongs after a display change. An
    /// arrangement seen before restores its own remembered layout exactly
    /// (dock/undock round-trips every widget to where the user put it, per
    /// arrangement). A brand-new arrangement is seeded by *migrating* each
    /// panel from where it sat on the previous screens — same screen if it
    /// survived, else the matching screen at the same fractional spot, scaled
    /// to the new screen's size — and recorded, so it's exact from then on.
    private func realignPanels() {
        let visible = NSScreen.screens.map(\.visibleFrame)
        guard !visible.isEmpty else { return }
        let key = arrangementKey
        let known = frameStore.layout(for: key) != nil
        var stranded = 0
        for (kind, panel) in panels.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if known {
                if let saved = frameStore.frame(for: kind, arrangement: key),
                   let spot = WidgetPlacement.rescued(saved, within: visible) {
                    if panel.frame != spot { panel.setFrame(spot, display: true) }
                    continue
                }
                // Known arrangement but this widget has no entry yet (it was
                // opened elsewhere): fall through to migrate it in.
            }
            let spot = migratedSpot(for: kind, panel: panel, within: visible, stranded: &stranded)
            if panel.frame != spot { panel.setFrame(spot, display: true) }
            // Record it so this arrangement restores exactly from now on.
            frameStore.save(spot, for: kind, arrangement: key, screens: visible)
        }
        lastScreens = visible
    }

    /// Where a panel should land on screens it has no saved spot for.
    /// Migration from the previous arrangement comes *first*: a display change
    /// re-anchors every global coordinate, so a stale frame can land on the
    /// wrong monitor by coincidence — `migrated` maps it through the screen it
    /// was actually on (and is a near no-op when that screen survived
    /// unchanged). Only with no previous screens to migrate from does the
    /// keep-if-on-a-live-screen rescue apply; fully stranded, the default
    /// cascade.
    private func migratedSpot(
        for kind: WidgetKind, panel: NSPanel, within visible: [CGRect], stranded: inout Int
    ) -> CGRect {
        if let spot = WidgetPlacement.migrated(panel.frame, from: lastScreens, to: visible) {
            return WidgetPlacement.fitted(clamped(spot, to: kind), within: visible)
        }
        if let spot = WidgetPlacement.rescued(panel.frame, within: visible) { return spot }
        defer { stranded += 1 }
        return WidgetPanel.cascadeFrame(size: panel.frame.size, index: stranded)
            ?? WidgetPlacement.fitted(panel.frame, within: visible)
    }

    /// Migration scales a frame by the screen ratio; the widget's own resize
    /// bounds still win.
    private func clamped(_ frame: CGRect, to kind: WidgetKind) -> CGRect {
        var f = frame
        f.size.width = min(max(f.width, kind.minSize.width), kind.maxSize.width)
        f.size.height = min(max(f.height, kind.minSize.height), kind.maxSize.height)
        return f
    }

    /// The spot a newly shown widget belongs in: its saved frame in the
    /// current arrangement, else its spot in the most recently used layout
    /// migrated over, else the pre-arrangement legacy frame — nil (caller
    /// cascades) only for a widget never placed anywhere.
    private func restoredFrame(for kind: WidgetKind) -> CGRect? {
        let visible = NSScreen.screens.map(\.visibleFrame)
        let key = arrangementKey
        if let saved = frameStore.frame(for: kind, arrangement: key),
           let spot = WidgetPlacement.rescued(saved, within: visible) {
            return spot
        }
        if let recent = frameStore.mostRecentLayout(excluding: key),
           let old = recent.frame(for: kind),
           let spot = WidgetPlacement.migrated(old, from: recent.screenRects, to: visible) {
            return WidgetPlacement.fitted(clamped(spot, to: kind), within: visible)
        }
        if let legacy = frameStore.legacyFrame(for: kind),
           let spot = WidgetPlacement.rescued(legacy, within: visible) {
            return spot
        }
        return nil
    }

    /// Remembers a widget's frame in the current arrangement's layout — called
    /// when the user finishes a drag/resize and when a widget is placed.
    private func persistFrame(_ frame: CGRect, for kind: WidgetKind) {
        frameStore.save(
            frame, for: kind, arrangement: arrangementKey,
            screens: NSScreen.screens.map(\.visibleFrame)
        )
    }

    // MARK: - Level mode

    @objc private func appActivityChanged() {
        // Only behind-icons panels change with app activity (they surface for
        // arranging); the other modes are activity-independent.
        guard levelMode == .behindIcons else { return }
        applyLevels()
    }

    private func applyLevels() {
        for panel in panels.values {
            WidgetPanel.apply(mode: levelMode, appActive: NSApp.isActive, to: panel)
        }
    }

    // MARK: - Show / hide

    func isVisible(_ kind: WidgetKind) -> Bool { visible.contains(kind) }

    func toggle(_ kind: WidgetKind) {
        isVisible(kind) ? hide(kind) : show(kind)
    }

    func show(_ kind: WidgetKind) {
        guard panels[kind] == nil else { return }
        let panel = WidgetPanel.make(
            kind: kind,
            mode: levelMode,
            appActive: NSApp.isActive,
            frame: restoredFrame(for: kind),
            cascadeIndex: panels.count,
            model: model,
            settings: settings,
            onClose: { [weak self] in self?.hide(kind) },
            onFrameChanged: { [weak self] frame in self?.persistFrame(frame, for: kind) }
        )
        panels[kind] = panel
        // Record where it landed, so even a first-ever (cascaded) spot belongs
        // to this arrangement's layout.
        persistFrame(panel.frame, for: kind)
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
