import CoreGraphics
import Foundation

/// Pure geometry for keeping widget panels on real screens. Deliberately free
/// of NSScreen so the rules are unit-testable: callers pass the screens'
/// visible frames as plain rects (AppKit global coordinates).
enum WidgetPlacement {
    /// The frame moved (and, if it can't fit, shrunk) so it sits fully inside
    /// the most appropriate screen: the one it overlaps most, else the nearest.
    /// A frame that already fits comes back unchanged; no screens, unchanged.
    static func fitted(_ frame: CGRect, within screens: [CGRect]) -> CGRect {
        guard let screen = bestScreen(for: frame, in: screens) else { return frame }
        var f = frame
        f.size.width = min(f.width, screen.width)
        f.size.height = min(f.height, screen.height)
        f.origin.x = min(max(f.minX, screen.minX), screen.maxX - f.width)
        f.origin.y = min(max(f.minY, screen.minY), screen.maxY - f.height)
        return f
    }

    /// Where a remembered frame should go on the current screens: unchanged
    /// when it fits, nudged fully on-screen when it merely pokes past an edge
    /// (a Dock or resolution change must not cost the user their placement),
    /// or nil when it's fully stranded — its display is gone — and the caller
    /// should pick a fresh spot instead (clamping strands from the same dead
    /// display would pile them onto one edge). No screens: unchanged.
    static func rescued(_ frame: CGRect, within screens: [CGRect]) -> CGRect? {
        guard !screens.isEmpty else { return frame }
        guard screens.contains(where: { $0.intersects(frame) }) else { return nil }
        return fitted(frame, within: screens)
    }

    /// The screen containing most of the frame, else the closest one.
    private static func bestScreen(for frame: CGRect, in screens: [CGRect]) -> CGRect? {
        func overlap(_ s: CGRect) -> CGFloat {
            let i = s.intersection(frame)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 {
            return best
        }
        func distanceSquared(_ s: CGRect) -> CGFloat {
            let dx = max(max(s.minX - frame.midX, frame.midX - s.maxX), 0)
            let dy = max(max(s.minY - frame.midY, frame.midY - s.maxY), 0)
            return dx * dx + dy * dy
        }
        return screens.min(by: { distanceSquared($0) < distanceSquared($1) })
    }
}
