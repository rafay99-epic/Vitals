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

    // MARK: migrated — carrying widgets to a brand-new display arrangement

    func testWidgetOnASurvivingExternalKeepsItsSpotAfterTheLaptopCloses() {
        // Laptop closes: the external is now the sole, primary screen at the
        // origin. It's the same physical panel (same size), just re-anchored,
        // so a widget centered on it should land dead-center on the new
        // arrangement too.
        let oldScreens = [laptop, external]
        let newScreens = [CGRect(x: 0, y: 0, width: external.width, height: external.height)]
        let center = CGPoint(x: external.midX, y: external.midY)
        let frame = CGRect(x: center.x - 106, y: center.y - 59, width: 212, height: 118)

        let migrated = WidgetPlacement.migrated(frame, from: oldScreens, to: newScreens)

        XCTAssertEqual(
            migrated,
            CGRect(x: 854, y: 541, width: 212, height: 118),
            "a size-matched screen should keep the widget's spot even though every coordinate was re-anchored"
        )
    }

    func testWidgetOnAVanishedLaptopLandsOnTheNewPrimaryAtTheSameFractionalCorner() {
        // The laptop panel itself is gone; only the (now-primary) external
        // remains. The widget should fall back to the position-matched new
        // primary, keeping its corner and growing by the screen's size ratio.
        let oldScreens = [laptop, external]
        let newScreens = [CGRect(x: 0, y: 0, width: 1920, height: 1200)]
        let frame = CGRect(x: 1250, y: 780, width: 212, height: 118) // top-right area of the laptop

        guard let migrated = WidgetPlacement.migrated(frame, from: oldScreens, to: newScreens) else {
            return XCTFail("expected a migrated frame")
        }
        let target = newScreens[0]
        let scale = min(target.width / laptop.width, target.height / laptop.height)

        XCTAssertEqual(migrated.width, frame.width * scale, accuracy: 0.01,
                        "size should scale by the screen ratio")
        XCTAssertEqual(migrated.height, frame.height * scale, accuracy: 0.01)

        let oldFx = (frame.midX - laptop.minX) / laptop.width
        let oldFy = (frame.midY - laptop.minY) / laptop.height
        let newFx = (migrated.midX - target.minX) / target.width
        let newFy = (migrated.midY - target.minY) / target.height
        XCTAssertEqual(newFx, oldFx, accuracy: 0.001, "must stay in the same fractional corner")
        XCTAssertEqual(newFy, oldFy, accuracy: 0.001)
        XCTAssertGreaterThan(oldFx, 0.5, "sanity: this frame really is on the right half")
        XCTAssertGreaterThan(oldFy, 0.5, "sanity: this frame really is on the top half")
    }

    func testMigrationFallsBackToListPositionWhenNoScreenMatchesBySize() {
        // Neither new screen matches an old one by size, so pairing must fall
        // back to list position: a widget on the *second* old screen should
        // land on the *second* new screen, not just "the closest".
        let oldScreens = [
            CGRect(x: 0, y: 0, width: 1000, height: 700),
            CGRect(x: 1000, y: 0, width: 1200, height: 800),
        ]
        let newScreens = [
            CGRect(x: 0, y: 0, width: 900, height: 650),
            CGRect(x: 900, y: 0, width: 1100, height: 750),
        ]
        let frame = CGRect(x: 1100, y: 100, width: 100, height: 100) // on the second old screen

        guard let migrated = WidgetPlacement.migrated(frame, from: oldScreens, to: newScreens) else {
            return XCTFail("expected a migrated frame")
        }
        XCTAssertTrue(newScreens[1].contains(migrated), "index fallback should target the second new screen")
        XCTAssertFalse(newScreens[0].intersects(migrated))
    }

    func testBigScreenToSmallScreenShrinksTheWidget() {
        let bigScreen = CGRect(x: 0, y: 0, width: 1920, height: 1175)
        let smallScreen = CGRect(x: 0, y: 0, width: 1512, height: 948)
        let frame = CGRect(x: 800, y: 600, width: 212, height: 118)

        guard let migrated = WidgetPlacement.migrated(frame, from: [bigScreen], to: [smallScreen]) else {
            return XCTFail("expected a migrated frame")
        }
        let scale = min(smallScreen.width / bigScreen.width, smallScreen.height / bigScreen.height)
        XCTAssertEqual(migrated.width, frame.width * scale, accuracy: 0.01)
        XCTAssertEqual(migrated.height, frame.height * scale, accuracy: 0.01)
        XCTAssertLessThan(migrated.width, frame.width)
        XCTAssertLessThan(migrated.height, frame.height)
        XCTAssertTrue(smallScreen.contains(migrated))
    }

    func testScaleCannotGrowPastDouble() {
        // A tiny old screen and a huge new one would naively balloon the
        // widget 20x; the scale must clamp at 2x.
        let oldScreens = [CGRect(x: 0, y: 0, width: 200, height: 150)]
        let newScreens = [CGRect(x: 0, y: 0, width: 4000, height: 3000)]
        let frame = CGRect(x: 20, y: 20, width: 100, height: 80)

        guard let migrated = WidgetPlacement.migrated(frame, from: oldScreens, to: newScreens) else {
            return XCTFail("expected a migrated frame")
        }
        XCTAssertEqual(migrated.width, 200, accuracy: 0.01)
        XCTAssertEqual(migrated.height, 160, accuracy: 0.01)
    }

    func testScaleCannotShrinkBelowHalf() {
        // A huge old screen and a modest new one would naively shrink the
        // widget to 1/5 size; the scale must floor at 0.5x.
        let oldScreens = [CGRect(x: 0, y: 0, width: 4000, height: 3000)]
        let newScreens = [CGRect(x: 0, y: 0, width: 800, height: 600)]
        let frame = CGRect(x: 1000, y: 1000, width: 200, height: 150)

        guard let migrated = WidgetPlacement.migrated(frame, from: oldScreens, to: newScreens) else {
            return XCTFail("expected a migrated frame")
        }
        XCTAssertEqual(migrated.width, 100, accuracy: 0.01)
        XCTAssertEqual(migrated.height, 75, accuracy: 0.01)
    }

    func testMigratedWithNoOldScreensReturnsNil() {
        let frame = CGRect(x: 0, y: 0, width: 212, height: 118)
        XCTAssertNil(WidgetPlacement.migrated(frame, from: [], to: [laptop]))
    }

    func testMigratedWithNoNewScreensReturnsNil() {
        let frame = CGRect(x: 0, y: 0, width: 212, height: 118)
        XCTAssertNil(WidgetPlacement.migrated(frame, from: [laptop], to: []))
    }

    func testSimilarHeightMonitorsAreNeverMistakenForEachOther() {
        // A 1920×1080 and a 1920×1200 (visible heights 1055/1175, 120 pt
        // apart) are distinct physical displays — a widget must follow its
        // own monitor even when the arrangement re-anchors and reorders.
        let old1080 = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let old1200 = CGRect(x: 1920, y: 0, width: 1920, height: 1175)
        let new1200 = CGRect(x: 0, y: 0, width: 1920, height: 1175)
        let new1080 = CGRect(x: 1920, y: 0, width: 1920, height: 1055)
        let onThe1200 = CGRect(x: 3500, y: 1000, width: 212, height: 118) // top-right of the old 1200p
        guard let spot = WidgetPlacement.migrated(onThe1200, from: [old1080, old1200], to: [new1200, new1080]) else {
            return XCTFail("expected a migrated frame")
        }
        XCTAssertTrue(new1200.contains(spot), "the widget must follow the 1200p display, not the same-width 1080p")
    }

    func testSideDockWidthInsetDoesNotBreakScreenPairing() {
        // The Dock moved to the surviving screen's edge, shaving ~90 pt off
        // its visible width. Still the same physical display — its widget
        // must not fall back to a position-matched different screen.
        let oldA = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let oldB = CGRect(x: 1920, y: 0, width: 1920, height: 1175)
        let newBWithDock = CGRect(x: 0, y: 0, width: 1830, height: 1175)
        let newA = CGRect(x: 1830, y: 0, width: 1920, height: 1055)
        let onB = CGRect(x: 3500, y: 1000, width: 212, height: 118)
        guard let spot = WidgetPlacement.migrated(onB, from: [oldA, oldB], to: [newBWithDock, newA]) else {
            return XCTFail("expected a migrated frame")
        }
        XCTAssertTrue(newBWithDock.contains(spot), "a side Dock must not unpair a widget from its own display")
    }

    func testMigratedResultAlwaysFitsInsideTheTargetScreen() {
        // A widget flush against the old screen's top-right corner, migrated
        // to a short-and-wide target: the naive fractional-anchor placement
        // would overhang the bottom edge. The final result must still fit.
        let oldScreen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let newScreen = CGRect(x: 0, y: 0, width: 1000, height: 200)
        let frame = CGRect(x: 700, y: 520, width: 100, height: 80) // flush with the old screen's top-right corner

        guard let migrated = WidgetPlacement.migrated(frame, from: [oldScreen], to: [newScreen]) else {
            return XCTFail("expected a migrated frame")
        }
        XCTAssertTrue(newScreen.contains(migrated), "a migrated widget must never hang off its new screen")
    }
}
