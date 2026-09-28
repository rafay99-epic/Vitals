import Testing
@testable import Vitals

/// The GPU reader must never fabricate values: a live reading, *when present*,
/// stays in range. Never requires a GPU; CI hosts may have no IOAccelerator.
struct GPUSensorTests {
    @Test func liveReadingStaysInRange() {
        guard let snapshot = GPUSampler().sample() else { return }
        if let utilization = snapshot.utilization {
            #expect(utilization >= 0 && utilization <= 100)
        }
        if let total = snapshot.memoryTotal {
            #expect(total > 0)
        }
    }
}
