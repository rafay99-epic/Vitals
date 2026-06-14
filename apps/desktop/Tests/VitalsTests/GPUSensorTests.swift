import Testing
@testable import Vitals

/// The GPU reader must never fabricate values. These tests lock the pure
/// `memoryFraction` math and assert that a live reading, *when present*, stays
/// in range. They never require a GPU to exist — CI runs on virtualized macOS
/// hosts that may have no readable IOAccelerator, and a "GPU must exist" test
/// would wrongly gate the release there.
struct GPUSensorTests {
    @Test func memoryFractionIsUsedOverTotal() {
        let snapshot = GPUSnapshot(name: "Test GPU", utilization: 50,
                                   memoryUsed: 2_000_000_000, memoryTotal: 8_000_000_000)
        #expect(snapshot.memoryFraction == 0.25)
    }

    @Test func memoryFractionClampsToOne() {
        // In-use can momentarily exceed the recommended working set.
        let snapshot = GPUSnapshot(name: nil, utilization: nil,
                                   memoryUsed: 9_000_000_000, memoryTotal: 8_000_000_000)
        #expect(snapshot.memoryFraction == 1)
    }

    @Test func memoryFractionIsNilWhenIncomplete() {
        #expect(GPUSnapshot(name: nil, utilization: nil, memoryUsed: nil, memoryTotal: 8).memoryFraction == nil)
        #expect(GPUSnapshot(name: nil, utilization: nil, memoryUsed: 8, memoryTotal: nil).memoryFraction == nil)
        #expect(GPUSnapshot(name: nil, utilization: nil, memoryUsed: 8, memoryTotal: 0).memoryFraction == nil)
    }

    @Test func liveReadingStaysInRange() {
        guard let snapshot = GPUSampler().sample() else { return }  // no GPU here → nothing to check
        if let utilization = snapshot.utilization {
            #expect(utilization >= 0 && utilization <= 100)
        }
        if let fraction = snapshot.memoryFraction {
            #expect(fraction >= 0 && fraction <= 1)
        }
    }
}
