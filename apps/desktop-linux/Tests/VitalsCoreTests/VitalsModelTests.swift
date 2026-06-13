import XCTest
@testable import VitalsCore

final class VitalsModelTests: XCTestCase {

    private func snapshot(cpuTemps: [Double], usage: Double?) -> Snapshot {
        Snapshot(
            temps: cpuTemps.enumerated().map { TempReading(label: "Core \($0.offset)", celsius: $0.element, kind: .cpu) },
            cpuUsage: usage,
            memory: MemorySnapshot(total: 16_000_000_000, available: 8_000_000_000, free: 4_000_000_000, cached: 4_000_000_000, swapTotal: 0, swapUsed: 0),
            chipName: "Test CPU"
        )
    }

    func testAverageAndHottest() {
        var history = VitalsModel.History()
        let state = VitalsModel.derive(snapshot(cpuTemps: [40, 50, 60], usage: 25), history: &history)
        XCTAssertEqual(state.cpuTempAvg ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(state.hottestTemp, 60)
        XCTAssertEqual(state.hottestLabel, "Core 2")
        XCTAssertEqual(state.chipName, "Test CPU")
        XCTAssertEqual(state.dieTemps.count, 3)
        XCTAssertFalse(state.sensorsUnavailable)
    }

    func testCPUSeriesStartsAfterFirstUsageButTempDoesNot() {
        var history = VitalsModel.History()
        // First tick: no usage delta yet → no CPU point, but temp/mem start now.
        _ = VitalsModel.derive(snapshot(cpuTemps: [45], usage: nil), history: &history)
        XCTAssertEqual(history.cpu.count, 0)
        XCTAssertEqual(history.temp.count, 1)
        XCTAssertEqual(history.mem.count, 1)
        // Subsequent ticks with usage → CPU series accumulates.
        _ = VitalsModel.derive(snapshot(cpuTemps: [45], usage: 30), history: &history)
        _ = VitalsModel.derive(snapshot(cpuTemps: [46], usage: 35), history: &history)
        XCTAssertEqual(history.cpu.count, 2)
    }

    func testChartsFillWithoutTemperatureSensor() {
        var history = VitalsModel.History()
        // A VM with no temp sensors: CPU and memory charts must still populate.
        _ = VitalsModel.derive(snapshot(cpuTemps: [], usage: 20), history: &history)
        let state = VitalsModel.derive(snapshot(cpuTemps: [], usage: 22), history: &history)
        XCTAssertTrue(state.tempHistory.isEmpty, "no temp sensor → empty temp chart, not a fake line")
        XCTAssertEqual(history.cpu.count, 2)
        XCTAssertFalse(state.cpuHistory.isEmpty)
        XCTAssertFalse(state.memHistory.isEmpty)
    }

    func testHistoryIsCappedAndDownsampled() {
        var history = VitalsModel.History()
        var state = DashboardState()
        for i in 0..<1000 {
            state = VitalsModel.derive(snapshot(cpuTemps: [Double(i % 80)], usage: Double(i % 100)), history: &history)
        }
        XCTAssertLessThanOrEqual(history.cpu.count, VitalsModel.maxHistory)
        XCTAssertLessThanOrEqual(state.cpuHistory.count, VitalsModel.chartPoints)
        XCTAssertEqual(state.tempHistory.count, state.cpuHistory.count)
    }

    func testSensorsUnavailableOnEmptySnapshot() {
        var history = VitalsModel.History()
        let state = VitalsModel.derive(Snapshot(), history: &history)
        XCTAssertTrue(state.sensorsUnavailable)
        XCTAssertTrue(state.hasLoaded)
    }
}
