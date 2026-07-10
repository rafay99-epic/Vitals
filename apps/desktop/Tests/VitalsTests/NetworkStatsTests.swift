import Testing
import Foundation
@testable import Vitals

/// Lock the pure, hardware-free seams of `NetworkStats`: the rate delta (which
/// must never report a negative or a spike on a counter reset), the throughput /
/// byte formatting (deterministic, base-1000, adaptive precision), and the
/// interface-inclusion guard that keeps virtual/loopback interfaces from
/// double-counting traffic. None of these touch the kernel, CoreWLAN, or the
/// network, so they run anywhere `swift test` does.
struct NetworkStatsTests {
    // MARK: CounterRate.perSecond (shared by NetworkStats + DiskStats)

    @Test func normalDeltaIsBytesOverElapsed() {
        // 1000 bytes over 2 seconds → 500 B/s.
        #expect(CounterRate.perSecond(previous: 1000, current: 2000, elapsed: 2) == 500)
    }

    @Test func zeroElapsedIsZero() {
        // No time passed → no honest rate to report.
        #expect(CounterRate.perSecond(previous: 0, current: 5000, elapsed: 0) == 0)
    }

    @Test func counterDecreaseIsZero() {
        // Interface re-created / counter reset: report 0, never a negative.
        #expect(CounterRate.perSecond(previous: 9000, current: 100, elapsed: 1) == 0)
    }

    @Test func equalCountersAreZero() {
        #expect(CounterRate.perSecond(previous: 4242, current: 4242, elapsed: 1) == 0)
    }

    @Test func largeValuesDoNotOverflow() {
        // ~10 GB delta over 1 s — well within Double range, no wraparound.
        let previous: UInt64 = 5_000_000_000
        let current: UInt64 = 15_000_000_000
        #expect(CounterRate.perSecond(previous: previous, current: current, elapsed: 1) == 10_000_000_000)
    }

    // MARK: NetworkFormat.rate

    @Test func rateFormatsAcrossMagnitudes() {
        #expect(NetworkFormat.rate(0) == "0 B/s")
        #expect(NetworkFormat.rate(-5) == "0 B/s")          // never a negative rate
        #expect(NetworkFormat.rate(540) == "540 B/s")
        #expect(NetworkFormat.rate(999) == "999 B/s")
        #expect(NetworkFormat.rate(1000) == "1.0 KB/s")     // rolls to KB with a decimal
        #expect(NetworkFormat.rate(540_000) == "540 KB/s")  // hundreds of KB → integer
        #expect(NetworkFormat.rate(1_200_000) == "1.2 MB/s")
        #expect(NetworkFormat.rate(2_500_000_000) == "2.5 GB/s")
    }

    @Test func compactRateFormatsAcrossMagnitudes() {
        // The menu-bar form: same tiers as `rate`, unit shrunk to one letter.
        #expect(NetworkFormat.compactRate(0) == "0B")
        #expect(NetworkFormat.compactRate(-5) == "0B")
        #expect(NetworkFormat.compactRate(540) == "540B")
        #expect(NetworkFormat.compactRate(1000) == "1.0K")
        #expect(NetworkFormat.compactRate(540_000) == "540K")
        #expect(NetworkFormat.compactRate(1_200_000) == "1.2M")
        #expect(NetworkFormat.compactRate(2_500_000_000) == "2.5G")
    }

    // MARK: NetworkFormat.bytes

    @Test func bytesFormatsAcrossMagnitudes() {
        #expect(NetworkFormat.bytes(0) == "0 B")
        #expect(NetworkFormat.bytes(512) == "512 B")
        #expect(NetworkFormat.bytes(1000) == "1.0 KB")
        #expect(NetworkFormat.bytes(1_400_000_000) == "1.4 GB")
        #expect(NetworkFormat.bytes(2_000_000_000_000) == "2.0 TB")
    }

    // MARK: interface inclusion

    @Test func countsPhysicalInterfacesOnly() {
        // Physical enX links are counted…
        #expect(NetworkStats.isCountedInterface("en0"))
        #expect(NetworkStats.isCountedInterface("en5"))
        // …virtual / loopback families are excluded so VPN & AirDrop traffic
        // that rides a physical interface isn't double-counted.
        #expect(!NetworkStats.isCountedInterface("lo0"))
        #expect(!NetworkStats.isCountedInterface("utun0"))
        #expect(!NetworkStats.isCountedInterface("awdl0"))
        #expect(!NetworkStats.isCountedInterface("llw0"))
        #expect(!NetworkStats.isCountedInterface("bridge0"))
        #expect(!NetworkStats.isCountedInterface("gif0"))
        #expect(!NetworkStats.isCountedInterface("stf0"))
        #expect(!NetworkStats.isCountedInterface("ap1"))
        #expect(!NetworkStats.isCountedInterface("anpi0"))
        #expect(!NetworkStats.isCountedInterface("XHC20"))
    }
}
