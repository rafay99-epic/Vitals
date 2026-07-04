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
        // A legacy 11-column line predates network logging — honest nil, not 0.
        #expect(sample?.netInBps == nil)
        #expect(sample?.netOutBps == nil)
    }

    @Test func parsesV2RowWithNetworkColumns() {
        let line = Substring("2026-06-16T01:02:03Z,43.5,52.6,,1200,12.3,10.40,Nominal,87,49.0,0.79,125000,34000")
        let sample = HistoryReader.parse(line)
        #expect(sample?.netInBps == 125_000)
        #expect(sample?.netOutBps == 34_000)
        // Blank trailing columns (no network reading that tick) → nil.
        let blank = Substring("2026-06-16T01:02:03Z,43.5,52.6,,1200,12.3,10.40,Nominal,87,49.0,0.79,,")
        #expect(HistoryReader.parse(blank)?.netInBps == nil)
    }

    @Test func rejectsHeaderAndMalformed() {
        let header = Substring("timestamp,avg_cpu_temp_c,hottest_cpu_temp_c,gpu_temp_c,fan_rpm,cpu_usage_pct,memory_used_gb,thermal_state,battery_pct,gpu_usage_pct,gpu_mem_used_gb")
        #expect(HistoryReader.parse(header) == nil)
        #expect(HistoryReader.parse(Substring("not,enough,fields")) == nil)
        #expect(HistoryReader.parse(Substring("")) == nil)
    }
}

/// The alert log is tab-separated so messages keep their commas; the parser must
/// read that back and reject anything malformed.
struct AlertLogTests {
    @Test func parsesTabSeparatedEvent() {
        let line = Substring("2026-06-16T01:02:03Z\tCPU temperature is 92°C — above your 90°C alert.")
        #expect(AlertLog.parse(line)?.message == "CPU temperature is 92°C — above your 90°C alert.")
    }

    @Test func rejectsMalformed() {
        #expect(AlertLog.parse(Substring("no tab present")) == nil)
        #expect(AlertLog.parse(Substring("not-a-date\tmessage")) == nil)
        #expect(AlertLog.parse(Substring("")) == nil)
    }
}
