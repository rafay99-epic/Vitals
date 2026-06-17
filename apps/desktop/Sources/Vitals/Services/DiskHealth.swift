import Foundation
import IOKit
import PrivateSensors

/// The internal SSD's health, straight from the drive's own NVMe SMART log —
/// wear, lifetime bytes written/read, power-on hours, power cycles, unsafe
/// shutdowns, spare blocks, temperature, and the controller's critical-warning
/// flag. Every figure is a real counter the drive reports; nothing is estimated
/// or invented. A Mac (or VM) that doesn't expose SMART returns nil rather than
/// a fabricated "100% healthy".
struct DiskHealthSnapshot {
    let model: String?
    let capacityBytes: Int64?
    /// The drive's own wear estimate (NVMe "percentage used"): 0 = fresh, 100 =
    /// the rated endurance has been consumed (it can read past 100).
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
    /// Composite temperature in °C, or nil when the drive doesn't report it.
    let temperature: Double?
    /// NVMe critical-warning bitfield; 0 = no warning.
    let criticalWarning: Int

    /// NVMe reports endurance in 512 000-byte "data units". Pure, for testing.
    static func bytes(dataUnits: UInt64) -> Int64 {
        let (product, overflow) = dataUnits.multipliedReportingOverflow(by: 512_000)
        if overflow || product > UInt64(Int64.max) { return Int64.max }
        return Int64(product)
    }

    /// Verdict from the NVMe critical-warning bitfield — any set bit means the
    /// controller is flagging a real problem (spare exhausted, read-only,
    /// degraded reliability, …). Pure, for testing.
    static func condition(criticalWarning: Int) -> String {
        criticalWarning == 0 ? "Healthy" : "Service recommended"
    }

    enum WearLevel { case normal, elevated, critical }

    /// Severity for the wear gauge. Folds in the controller's critical-warning
    /// flag and the spare-block threshold — not just wear % — so a flagged drive
    /// never shows a reassuring green. Pure, for testing.
    var wearLevel: WearLevel {
        if criticalWarning != 0 || percentUsed >= 100 { return .critical }
        if percentUsed >= 80 || availableSpare < availableSpareThreshold { return .elevated }
        return .normal
    }

    /// Power-on time as days once past a day, hours below. Pure, for testing.
    var poweredOnText: String {
        powerOnHours >= 48 ? "\(powerOnHours / 24) days" : "\(powerOnHours) h"
    }
}

enum DiskHealth {
    /// Reads the internal SSD's SMART log via the IOKit NVMe user client, then
    /// enriches it with the drive model/capacity from IORegistry. Returns nil
    /// when no SMART-capable device is present or the read fails — the caller
    /// shows an honest "unavailable" state, never zeros.
    static func read() -> DiskHealthSnapshot? {
        var raw = VitalsDiskSMART()
        guard vitals_nvme_smart_read(&raw) == 1, raw.valid == 1 else { return nil }

        let (model, capacity) = identity()
        // Composite temperature is in Kelvin; 0 means "not reported" → show nothing.
        let temperature = raw.temperature_k > 0 ? Double(raw.temperature_k) - 273.15 : nil

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
            criticalWarning: Int(raw.critical_warning)
        )
    }

    /// Best-effort model + capacity from the NVMe controller's IORegistry
    /// properties (mirrors `Battery.read`'s property read). Only reported when
    /// there is exactly **one** NVMe controller: the SMART log and this lookup
    /// match drives independently, so with an external NVMe attached we can't be
    /// sure they're the same drive — better to show no name/size than to pair
    /// the wrong one. Missing fields just don't render; nothing is faked.
    private static func identity() -> (model: String?, capacityBytes: Int64?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IONVMeController"), &iterator) == KERN_SUCCESS else {
            return (nil, nil)
        }
        defer { IOObjectRelease(iterator) }

        let controller = IOIteratorNext(iterator)
        guard controller != 0 else { return (nil, nil) }
        defer { IOObjectRelease(controller) }
        // More than one controller → ambiguous which drive; show nothing.
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
