import XCTest
@testable import Vitals

/// Locks the geometry that keeps desktop widgets on real screens: a widget on
/// an unplugged display must come back reachable, one that already fits must
/// not move.
final class WidgetPlacementTests: XCTestCase {
    // A laptop panel and an external above it, AppKit global coordinates.
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 948)
    private let external = CGRect(x: 685, y: 982, width: 1920, height: 1200)

    func testFrameAlreadyOnScreenIsUntouched() {
        let frame = CGRect(x: 500, y: 400, width: 212, height: 118)
        XCTAssertEqual(WidgetPlacement.fitted(frame, within: [laptop, external]), frame)
    }

    func testFramePokingPastAnEdgeIsClampedIn() {
        let frame = CGRect(x: 1400, y: 900, width: 212, height: 118)
        let fitted = WidgetPlacement.fitted(frame, within: [laptop])
        XCTAssertEqual(fitted.size, frame.size)
        XCTAssertEqual(fitted.maxX, laptop.maxX)
        XCTAssertEqual(fitted.maxY, laptop.maxY)
    }

    func testFrameOnVanishedDisplayMovesToNearestScreen() {
        // Where the external used to be, but only the laptop remains.
        let stranded = CGRect(x: 900, y: 1400, width: 212, height: 118)
        let fitted = WidgetPlacement.fitted(stranded, within: [laptop])
        XCTAssertTrue(laptop.contains(fitted), "stranded widget must land on the remaining screen")
        XCTAssertEqual(fitted.size, stranded.size)
    }

    func testFrameStraddlingScreensSnapsToTheOneItOverlapsMost() {
        // Mostly on the external, nudged past its bottom edge into the gap.
        let frame = CGRect(x: 900, y: 950, width: 212, height: 118)
        let fitted = WidgetPlacement.fitted(frame, within: [laptop, external])
        XCTAssertTrue(external.contains(fitted))
    }

    func testOversizedFrameIsShrunkToFit() {
        let huge = CGRect(x: 0, y: 0, width: 4000, height: 3000)
        let fitted = WidgetPlacement.fitted(huge, within: [laptop])
        XCTAssertEqual(fitted, laptop)
    }

    func testNoScreensLeavesFrameAlone() {
        let frame = CGRect(x: 5000, y: 5000, width: 212, height: 118)
        XCTAssertEqual(WidgetPlacement.fitted(frame, within: []), frame)
    }

    // MARK: rescued — keep, nudge, or give up

    func testRescueKeepsAFittingFrame() {
        let frame = CGRect(x: 500, y: 400, width: 212, height: 118)
        XCTAssertEqual(WidgetPlacement.rescued(frame, within: [laptop]), frame)
    }

    func testRescueNudgesAPartlyOffscreenFrameInsteadOfDiscardingIt() {
        // The Dock grew a little: the saved spot pokes 20 pt past the bottom.
        let frame = CGRect(x: 500, y: -20, width: 212, height: 118)
        let spot = WidgetPlacement.rescued(frame, within: [laptop])
        XCTAssertEqual(spot, CGRect(x: 500, y: 0, width: 212, height: 118),
                       "a nudge must preserve the user's placement, not reset it")
    }

    func testRescueGivesUpOnAFullyStrandedFrame() {
        // Entirely on a display that is no longer connected.
        let stranded = CGRect(x: 900, y: 1400, width: 212, height: 118)
        XCTAssertNil(WidgetPlacement.rescued(stranded, within: [laptop]),
                     "a stranded frame needs a fresh spot, not an edge pile-up")
    }

    func testRescueWithNoScreensLeavesFrameAlone() {
        let frame = CGRect(x: 5000, y: 5000, width: 212, height: 118)
        XCTAssertEqual(WidgetPlacement.rescued(frame, within: []), frame)
    }
}
