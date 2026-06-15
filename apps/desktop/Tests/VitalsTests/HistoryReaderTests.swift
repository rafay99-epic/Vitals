import Testing
import Foundation
@testable import Vitals

/// The history parser must read back exactly what the logger wrote, treat blank
/// columns as "unknown", and skip the header / any malformed line rather than
/// producing garbage samples.
struct HistoryReaderTests {
    @Test func parsesValidRow() {
        let line = Substring("2026-06-16T01:02:03Z,43.5,52.6,,1200,12.3,10.40,Nominal,87,49.0,0.79")
        let sample = HistoryReader.parse(line)
        #expect(sample?.avgTemp == 43.5)
        #expect(sample?.hottestTemp == 52.6)
        #expect(sample?.gpuTemp == nil)        // blank column → nil, not 0
        #expect(sample?.fanRPM == 1200)
        #expect(sample?.cpuUsage == 12.3)
        #expect(sample?.memoryGB == 10.40)
        #expect(sample?.thermalState == "Nominal")
        #expect(sample?.batteryPercent == 87)
        #expect(sample?.gpuUsage == 49.0)
        #expect(sample?.gpuMemoryGB == 0.79)
    }

    @Test func rejectsHeaderAndMalformed() {
        let header = Substring("timestamp,avg_cpu_temp_c,hottest_cpu_temp_c,gpu_temp_c,fan_rpm,cpu_usage_pct,memory_used_gb,thermal_state,battery_pct,gpu_usage_pct,gpu_mem_used_gb")
        #expect(HistoryReader.parse(header) == nil)
        #expect(HistoryReader.parse(Substring("not,enough,fields")) == nil)
        #expect(HistoryReader.parse(Substring("")) == nil)
    }
}
