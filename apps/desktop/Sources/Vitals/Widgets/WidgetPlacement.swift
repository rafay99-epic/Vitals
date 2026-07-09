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

    /// Where a frame from an *old* display arrangement should land on a *new*
    /// one it has never seen: the same fractional spot on the corresponding
    /// screen, with the size scaled by the screen ratio — so a widget laid out
    /// on a 24″ monitor arrives on the 14″ panel proportionally smaller, at
    /// the matching corner, instead of oversized in a pile. Screens pair by
    /// *size* first (a monitor that survived the change keeps its widgets even
    /// though closing the lid re-anchored every global coordinate), falling
    /// back to list position (callers pass `NSScreen.screens` order, primary
    /// first) — so widgets from a vanished laptop panel land on the new
    /// primary. Nil when either arrangement is empty — the caller should
    /// cascade instead.
    static func migrated(_ frame: CGRect, from oldScreens: [CGRect], to newScreens: [CGRect]) -> CGRect? {
        guard !newScreens.isEmpty,
              let source = bestScreen(for: frame, in: oldScreens),
              source.width > 0, source.height > 0,
              let sourceIndex = oldScreens.firstIndex(of: source) else { return nil }
        let target = matchedScreen(for: source, at: sourceIndex, in: newScreens)
        // Uniform scale (no distortion), bounded so an extreme resolution jump
        // can't collapse or balloon a widget past recognition.
        let scale = min(max(min(target.width / source.width, target.height / source.height), 0.5), 2)
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        // Anchor by fractional center so "top-right of my monitor" stays
        // top-right of the screen it moves to.
        let fx = (frame.midX - source.minX) / source.width
        let fy = (frame.midY - source.minY) / source.height
        let spot = CGRect(
            x: target.minX + fx * target.width - size.width / 2,
            y: target.minY + fy * target.height - size.height / 2,
            width: size.width, height: size.height
        )
        return fitted(spot, within: [target])
    }

    /// The new-arrangement screen a source screen's widgets should follow.
    /// Same size (height within a Dock/menu-bar tolerance, since these are
    /// visible frames) means it's almost certainly the same physical display —
    /// ties break toward the same list position. No size match means the
    /// display is gone; its widgets fall back to the position-matched screen
    /// (a vanished primary hands its widgets to the new primary).
    private static func matchedScreen(for source: CGRect, at sourceIndex: Int, in newScreens: [CGRect]) -> CGRect {
        let sameSize = newScreens.enumerated().filter {
            $0.element.width == source.width && abs($0.element.height - source.height) <= 200
        }
        if let match = sameSize.min(by: { abs($0.offset - sourceIndex) < abs($1.offset - sourceIndex) }) {
            return match.element
        }
        return newScreens[min(sourceIndex, newScreens.count - 1)]
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
