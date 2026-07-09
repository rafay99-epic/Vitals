import XCTest
@testable import Vitals

/// Locks the per-arrangement widget-frame persistence: each display
/// arrangement gets its own memory, reads are clamped to sane sizes, and the
/// store never grows without bound.
final class WidgetFrameStoreTests: XCTestCase {
    private static let suiteName = "vitals-frame-store-tests"
    private var defaults: UserDefaults!
    private var store: WidgetFrameStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
        store = WidgetFrameStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: arrangementKey

    func testArrangementKeyIsOrderInsensitive() {
        let a = CGRect(x: 0, y: 0, width: 1512, height: 948)
        let b = CGRect(x: 1512, y: 0, width: 1920, height: 1200)
        XCTAssertEqual(
            WidgetFrameStore.arrangementKey(for: [a, b]),
            WidgetFrameStore.arrangementKey(for: [b, a]),
            "the same set of screens must produce the same key regardless of NSScreen.screens order"
        )
    }

    func testArrangementKeyDiffersForDifferentGeometry() {
        let a = CGRect(x: 0, y: 0, width: 1512, height: 948)
        let bMoved = CGRect(x: 1512, y: 0, width: 1920, height: 1200)
        let bResized = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        XCTAssertNotEqual(
            WidgetFrameStore.arrangementKey(for: [a, bMoved]),
            WidgetFrameStore.arrangementKey(for: [a, bResized]),
            "a real geometry change (resize/reposition) must fork a different arrangement"
        )
    }

    // MARK: save / frame round-trip

    func testSaveAndFrameRoundTrip() {
        let key = WidgetFrameStore.arrangementKey(for: [CGRect(x: 0, y: 0, width: 1512, height: 948)])
        let frame = CGRect(x: 100, y: 100, width: 212, height: 118)
        store.save(frame, for: .cpu, arrangement: key, screens: [CGRect(x: 0, y: 0, width: 1512, height: 948)])
        XCTAssertEqual(store.frame(for: .cpu, arrangement: key), frame)
    }

    func testFrameForUnknownArrangementIsNil() {
        XCTAssertNil(store.frame(for: .cpu, arrangement: "never-seen"))
    }

    // MARK: clamping on read

    func testFrameClampsAnUndersizedPersistedFrameUpToTheMinimum() {
        let key = "arrangement-tiny"
        let tiny = CGRect(x: 10, y: 10, width: 50, height: 40) // below WidgetKind.cpu.minSize
        store.save(tiny, for: .cpu, arrangement: key, screens: [CGRect(x: 0, y: 0, width: 1512, height: 948)])

        let result = store.frame(for: .cpu, arrangement: key)
        XCTAssertEqual(result?.width, WidgetKind.cpu.minSize.width)
        XCTAssertEqual(result?.height, WidgetKind.cpu.minSize.height)
        XCTAssertEqual(result?.origin.x, tiny.origin.x, "clamping must only touch size, not position")
        XCTAssertEqual(result?.origin.y, tiny.origin.y)
    }

    func testFrameClampsAnOversizedPersistedFrameDownToTheMaximum() {
        let key = "arrangement-huge"
        let huge = CGRect(x: 10, y: 10, width: 1000, height: 900) // above WidgetKind.cpu.maxSize
        store.save(huge, for: .cpu, arrangement: key, screens: [CGRect(x: 0, y: 0, width: 1512, height: 948)])

        let result = store.frame(for: .cpu, arrangement: key)
        XCTAssertEqual(result?.width, WidgetKind.cpu.maxSize.width)
        XCTAssertEqual(result?.height, WidgetKind.cpu.maxSize.height)
    }

    // MARK: mostRecentLayout(excluding:)

    func testMostRecentLayoutExcludingReturnsTheNewestOtherLayout() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 948)]
        let keyA = "arrangement-a"
        let keyB = "arrangement-b"
        let keyC = "arrangement-c"
        let frame = CGRect(x: 0, y: 0, width: 212, height: 118)

        store.save(frame, for: .cpu, arrangement: keyA, screens: screens, now: Date(timeIntervalSince1970: 100))
        store.save(frame, for: .cpu, arrangement: keyB, screens: screens, now: Date(timeIntervalSince1970: 200))
        store.save(frame, for: .cpu, arrangement: keyC, screens: screens, now: Date(timeIntervalSince1970: 300))

        // Excluding the newest (C) should surface the next-newest (B), not A.
        let mostRecent = store.mostRecentLayout(excluding: keyC)
        XCTAssertEqual(mostRecent?.stamp, 200, "must return the newest layout other than the excluded key")
    }

    func testMostRecentLayoutExcludingItselfIgnoresOnlyThatLayout() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 948)]
        let key = "solo-arrangement"
        let frame = CGRect(x: 0, y: 0, width: 212, height: 118)
        store.save(frame, for: .cpu, arrangement: key, screens: screens, now: Date(timeIntervalSince1970: 100))

        XCTAssertNil(store.mostRecentLayout(excluding: key), "with only one layout, excluding it must leave nothing")
    }

    // MARK: pruning (maxLayouts = 16)

    func testSavingPastTheCapPrunesTheStalestArrangement() {
        let frame = CGRect(x: 0, y: 0, width: 212, height: 118)
        var keys: [Int: String] = [:]

        // 17 distinct arrangements, each with a strictly increasing stamp.
        for i in 1...17 {
            let screens = [CGRect(x: CGFloat(i), y: 0, width: 1000, height: 700)]
            let key = WidgetFrameStore.arrangementKey(for: screens)
            keys[i] = key
            store.save(frame, for: .cpu, arrangement: key, screens: screens, now: Date(timeIntervalSince1970: Double(i)))
        }

        XCTAssertNil(store.layout(for: keys[1]!), "the single stalest arrangement must be dropped once the cap is exceeded")
        XCTAssertNotNil(store.layout(for: keys[2]!), "the next-stalest survivor must be kept")
        XCTAssertNotNil(store.layout(for: keys[17]!), "the arrangement just saved must never be pruned")
    }

    // MARK: legacyFrame

    func testLegacyFrameReadsTheOldSingleFrameKey() {
        let key = WidgetFrameStore.legacyKey(for: .memory)
        defaults.set([50.0, 60.0, 212.0, 118.0], forKey: key)

        let frame = store.legacyFrame(for: .memory)
        XCTAssertEqual(frame, CGRect(x: 50, y: 60, width: 212, height: 118))
    }

    func testLegacyFrameClampsToKindBounds() {
        let key = WidgetFrameStore.legacyKey(for: .combined)
        defaults.set([0.0, 0.0, 10.0, 10.0], forKey: key) // far below WidgetKind.combined.minSize

        let frame = store.legacyFrame(for: .combined)
        XCTAssertEqual(frame?.width, WidgetKind.combined.minSize.width)
        XCTAssertEqual(frame?.height, WidgetKind.combined.minSize.height)
    }

    func testLegacyFrameIsNilWhenAbsent() {
        XCTAssertNil(store.legacyFrame(for: .gpu))
    }
}
