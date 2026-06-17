import Testing
import Foundation
@testable import Vitals

/// The P/E split is only honest if the per-core deltas are bucketed correctly
/// and the cluster ranges are trusted. Lock the pure aggregator: overall is
/// always computed; the split appears only when the ranges tile [0, coreCount)
/// exactly, and falls back to blended-only otherwise (never a fabricated split).
struct CPUUsageTests {
    // host_processor_info CPU_STATE order is user=0, system=1, idle=2, nice=3.
    private func core(busy: UInt32, idle: UInt32) -> [UInt32] { [busy, 0, idle, 0] }

    @Test func overallIsBusyOverTotal() {
        let prev = [core(busy: 0, idle: 0), core(busy: 0, idle: 0)]
        let now  = [core(busy: 50, idle: 50), core(busy: 50, idle: 50)]
        let usage = CPUUsageSampler.clusterUsage(ticks: now, previous: prev, clusters: nil)
        #expect(usage?.overall == 50)
        #expect(usage?.performance == nil)   // no clusters provided → blended only
        #expect(usage?.efficiency == nil)
    }

    @Test func splitsBusyPerfFromIdleEfficiency() {
        // 4 cores: E = [0,2) idle, P = [2,4) fully busy.
        let prev = Array(repeating: core(busy: 0, idle: 0), count: 4)
        let now = [core(busy: 0, idle: 100), core(busy: 0, idle: 100),
                   core(busy: 100, idle: 0), core(busy: 100, idle: 0)]
        let usage = CPUUsageSampler.clusterUsage(
            ticks: now, previous: prev, clusters: (performance: 2..<4, efficiency: 0..<2))
        #expect(usage?.performance == 100)
        #expect(usage?.efficiency == 0)
        #expect(usage?.overall == 50)   // 2 of 4 cores busy, equally weighted
    }

    @Test func splitDroppedWhenRangesDontTileCoreCount() {
        // Ranges that don't cover [0,4) exactly → no trusted split, overall still set.
        let prev = Array(repeating: core(busy: 0, idle: 0), count: 4)
        let now = Array(repeating: core(busy: 100, idle: 0), count: 4)
        let usage = CPUUsageSampler.clusterUsage(
            ticks: now, previous: prev, clusters: (performance: 2..<3, efficiency: 0..<2))
        #expect(usage?.overall == 100)
        #expect(usage?.performance == nil)
        #expect(usage?.efficiency == nil)
    }

    @Test func allIdleIsZero() {
        let usage = CPUUsageSampler.clusterUsage(
            ticks: [core(busy: 0, idle: 100)], previous: [core(busy: 0, idle: 0)], clusters: nil)
        #expect(usage?.overall == 0)
    }
}
