import CoreGraphics
import Foundation

/// Remembers where every widget lives *per display arrangement*, so the docked
/// layout (laptop closed, externals only) and the laptop layout are two
/// separate memories: plugging in or unplugging a display restores that
/// arrangement's own layout exactly instead of piling widgets onto the primary
/// screen. Deliberately NSScreen-free (callers pass plain rects) so it stays
/// unit-testable; all storage is UserDefaults.
struct WidgetFrameStore {
    /// One arrangement's memory: the screens it was recorded on (visible
    /// frames, `NSScreen.screens` order — primary first) and each widget's
    /// frame, both as `[x, y, w, h]`. `stamp` orders layouts by recency so a
    /// brand-new arrangement can migrate from the one used most recently.
    struct Layout: Codable {
        var screens: [[Double]]
        var frames: [String: [Double]]
        var stamp: Double

        var screenRects: [CGRect] { screens.compactMap(Self.rect(from:)) }

        func frame(for kind: WidgetKind) -> CGRect? {
            frames[kind.rawValue].flatMap(Self.rect(from:))
        }

        static func rect(from values: [Double]) -> CGRect? {
            guard values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }

        static func values(from rect: CGRect) -> [Double] {
            [rect.origin.x, rect.origin.y, rect.width, rect.height]
        }
    }

    let defaults: UserDefaults

    private static let layoutsKey = "vitals.widget.layouts"
    /// Keep the most recent handful; a hot-desking user won't accumulate an
    /// unbounded blob of dead arrangements.
    private static let maxLayouts = 16

    /// A stable identity for a display arrangement: every screen's *full*
    /// frame (position + size in global coordinates). Full frames, not visible
    /// frames, so a Dock resize or menu-bar change doesn't fork a "new"
    /// arrangement. Sorted so enumeration order can't matter.
    static func arrangementKey(for screenFrames: [CGRect]) -> String {
        screenFrames
            .map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width))x\(Int($0.height))" }
            .sorted()
            .joined(separator: "|")
    }

    func layout(for key: String) -> Layout? { allLayouts()[key] }

    /// The most recently used layout other than `key` — the migration source
    /// when `key` has never been seen.
    func mostRecentLayout(excluding key: String) -> Layout? {
        allLayouts().filter { $0.key != key }.max(by: { $0.value.stamp < $1.value.stamp })?.value
    }

    func frame(for kind: WidgetKind, arrangement key: String) -> CGRect? {
        clamped(layout(for: key)?.frame(for: kind), to: kind)
    }

    /// Records one widget's frame in an arrangement's layout (creating the
    /// layout from `screens` if this is the arrangement's first save) and
    /// stamps it most-recent. `now` is injected for tests.
    func save(
        _ frame: CGRect, for kind: WidgetKind, arrangement key: String,
        screens: [CGRect], now: Date = Date()
    ) {
        var layouts = allLayouts()
        var layout = layouts[key] ?? Layout(screens: [], frames: [:], stamp: 0)
        layout.screens = screens.map(Layout.values(from:))
        layout.frames[kind.rawValue] = Layout.values(from: frame)
        layout.stamp = now.timeIntervalSince1970
        layouts[key] = layout
        // Drop the stalest arrangements past the cap (never the one just saved).
        while layouts.count > Self.maxLayouts,
              let stalest = layouts.filter({ $0.key != key }).min(by: { $0.value.stamp < $1.value.stamp }) {
            layouts.removeValue(forKey: stalest.key)
        }
        persist(layouts)
    }

    /// Re-stamps an arrangement most-recent without changing its frames —
    /// called when the user *returns* to an arrangement (no drag involved), so
    /// migration seeds from the layout actually used last and pruning never
    /// evicts a layout that's merely stable. No-op for an unknown key.
    func touch(_ key: String, now: Date = Date()) {
        var layouts = allLayouts()
        guard var layout = layouts[key] else { return }
        layout.stamp = now.timeIntervalSince1970
        layouts[key] = layout
        persist(layouts)
    }

    /// The pre-arrangement single saved frame (`vitals.widget.frame.<kind>`),
    /// kept as a read-only fallback so an update doesn't cost anyone their
    /// existing placement. Clamped to the kind's size bounds like every read.
    func legacyFrame(for kind: WidgetKind) -> CGRect? {
        guard let values = defaults.array(forKey: Self.legacyKey(for: kind)) as? [Double] else { return nil }
        return clamped(Layout.rect(from: values), to: kind)
    }

    static func legacyKey(for kind: WidgetKind) -> String { "vitals.widget.frame.\(kind.rawValue)" }

    /// A widget can't come back collapsed or ballooned past its resize bounds,
    /// whatever was persisted.
    private func clamped(_ frame: CGRect?, to kind: WidgetKind) -> CGRect? {
        guard var f = frame else { return nil }
        f.size.width = min(max(f.width, kind.minSize.width), kind.maxSize.width)
        f.size.height = min(max(f.height, kind.minSize.height), kind.maxSize.height)
        return f
    }

    private func allLayouts() -> [String: Layout] {
        guard let data = defaults.data(forKey: Self.layoutsKey),
              let layouts = try? JSONDecoder().decode([String: Layout].self, from: data)
        else { return [:] }
        return layouts
    }

    private func persist(_ layouts: [String: Layout]) {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: Self.layoutsKey)
    }
}
