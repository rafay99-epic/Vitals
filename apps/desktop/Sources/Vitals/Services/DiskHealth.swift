import Foundation
import IOKit
import PrivateSensors

/// The internal SSD's NVMe SMART log.
struct DiskHealthSnapshot {
    let model: String?
    let capacityBytes: Int64?
    /// NVMe "percentage used": 0 = fresh, 100 = rated endurance consumed. Can exceed 100.
    let percentUsed: Int
    /// Lifetime bytes written / read (NVMe data units × 512 000).
    let bytesWritten: Int64
    let bytesRead: Int64
    let powerOnHours: Int
    let powerCycles: Int
    let unsafeShutdowns: Int
    let availableSpare: Int          // % remaining
    let availableSpareThreshold: Int // % at which the drive warns
    let mediaErrors: Int
    /// Composite temperature in °C, nil when not reported.
    let temperature: Double?
    /// NVMe critical-warning bitfield; any set bit is a controller-flagged problem.
    let criticalWarning: Int
    /// TRIM support from the Identify Controller ONCS field (the same source
    /// `system_profiler` uses). Nil when the drive didn't answer Identify.
    let trimSupported: Bool?

    var trimText: String {
        guard let trimSupported else { return "Unknown" }
        return trimSupported ? "Supported" : "Not supported"
    }

    /// NVMe reports endurance in 512 000-byte "data units". Saturates at Int64.max.
    static func bytes(dataUnits: UInt64) -> Int64 {
        let (product, overflow) = dataUnits.multipliedReportingOverflow(by: 512_000)
        if overflow || product > UInt64(Int64.max) { return Int64.max }
        return Int64(product)
    }

    static func condition(criticalWarning: Int) -> String {
        criticalWarning == 0 ? "Healthy" : "Service recommended"
    }

    enum WearLevel { case normal, elevated, critical }

    /// Folds in the critical-warning flag and spare threshold, not just wear %,
    /// so a flagged drive never shows green.
    var wearLevel: WearLevel {
        if criticalWarning != 0 || percentUsed >= 100 { return .critical }
        if percentUsed >= 80 || availableSpare < availableSpareThreshold { return .elevated }
        return .normal
    }

    var poweredOnText: String {
        guard powerOnHours >= 24 else { return "\(powerOnHours) h" }
        let days = powerOnHours / 24
        return days == 1 ? "1 day" : "\(days) days"
    }
}

enum DiskHealth {
    /// SMART log via the IOKit NVMe user client, plus model/capacity from
    /// IORegistry. Nil when no SMART-capable device exists or the read fails.
    static func read() -> DiskHealthSnapshot? {
        var raw = VitalsDiskSMART()
        guard vitals_nvme_smart_read(&raw) == 1, raw.valid == 1 else { return nil }

        let (model, capacity) = identity()
        // Kelvin; 0 means not reported.
        let temperature = raw.temperature_k > 0 ? Double(raw.temperature_k) - 273.15 : nil
        let trim: Bool? = raw.trim_known == 1 ? (raw.trim_supported == 1) : nil

        func clampInt(_ value: UInt64) -> Int { Int(min(value, UInt64(Int.max))) }

        return DiskHealthSnapshot(
            model: model,
            capacityBytes: capacity,
            percentUsed: Int(raw.percentage_used),
            bytesWritten: DiskHealthSnapshot.bytes(dataUnits: raw.data_units_written),
            bytesRead: DiskHealthSnapshot.bytes(dataUnits: raw.data_units_read),
            powerOnHours: clampInt(raw.power_on_hours),
            powerCycles: clampInt(raw.power_cycles),
            unsafeShutdowns: clampInt(raw.unsafe_shutdowns),
            availableSpare: Int(raw.available_spare),
            availableSpareThreshold: Int(raw.available_spare_threshold),
            mediaErrors: clampInt(raw.media_errors),
            temperature: temperature,
            criticalWarning: Int(raw.critical_warning),
            trimSupported: trim
        )
    }

    /// Model + capacity from the NVMe controller's IORegistry properties. Only
    /// when there is exactly one controller: the SMART read and this lookup match
    /// drives independently, so with an external NVMe attached they could pair
    /// the wrong drive.
    private static func identity() -> (model: String?, capacityBytes: Int64?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IONVMeController"), &iterator) == KERN_SUCCESS else {
            return (nil, nil)
        }
        defer { IOObjectRelease(iterator) }

        let controller = IOIteratorNext(iterator)
        guard controller != 0 else { return (nil, nil) }
        defer { IOObjectRelease(controller) }
        let extra = IOIteratorNext(iterator)
        guard extra == 0 else { IOObjectRelease(extra); return (nil, nil) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(controller, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any]
        else { return (nil, nil) }

        let model = (props["Model Number"] as? String)?.trimmingCharacters(in: .whitespaces)
        let characteristics = props["Controller Characteristics"] as? [String: Any]
        let capacity = (characteristics?["capacity"] as? Int).map(Int64.init)
        return (model?.isEmpty == false ? model : nil, capacity)
    }
}
