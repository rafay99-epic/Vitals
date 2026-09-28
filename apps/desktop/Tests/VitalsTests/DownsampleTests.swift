import Testing
import Foundation
@testable import Vitals

/// `Array.thinned(to:)` thins history for chart rendering; it must
/// preserve order and endpoints and never duplicate samples (duplicate
/// ids break SwiftUI ForEach).
@MainActor
struct DownsampleTests {
    private func samples(_ count: Int) -> [VitalsModel.Sample] {
        (0..<count).map { i in
            let t = Date(timeIntervalSince1970: Double(i))
            return VitalsModel.Sample(
                id: t, time: t, averageCPU: 40, hottestCPU: 45, gpu: nil,
                gpuUsage: nil, usage: 10, memoryUsed: 0, swapUsed: 0, batteryPercent: nil, totalWatts: nil,
                batteryWatts: nil,
                netInPerSec: nil, netOutPerSec: nil, diskReadPerSec: nil, diskWritePerSec: nil
            )
        }
    }

    @Test func smallInputPassesThroughUntouched() {
        let input = samples(100)
        #expect(input.thinned(to: 400).count == 100)
    }

    @Test func thinsToRequestedCount() {
        #expect(samples(1800).thinned(to: 400).count == 400)
    }

    @Test func keepsFirstAndNewestSample() {
        let input = samples(1800)
        let thinned = input.thinned(to: 400)
        #expect(thinned.first?.id == input.first?.id)
        #expect(thinned.last?.id == input.last?.id)
    }

    @Test func neverDuplicatesSamples() {
        let thinned = samples(500).thinned(to: 400)
        let ids = Set(thinned.map(\.id))
        #expect(ids.count == thinned.count)
    }

    @Test func staysInChronologicalOrder() {
        let thinned = samples(1000).thinned(to: 64)
        let times = thinned.map { $0.time }
        #expect(times == times.sorted())
    }
}
