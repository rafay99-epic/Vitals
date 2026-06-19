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
