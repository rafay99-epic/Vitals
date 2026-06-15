import Foundation
import IOKit

struct BatterySnapshot {
    let percent: Double
    let isCharging: Bool
    let externalPower: Bool
    let fullyCharged: Bool
    /// Current maximum capacity relative to design capacity — the same
    /// figure System Settings calls "Maximum Capacity".
    let healthPercent: Double?
    let cycleCount: Int?
    /// Signed power flow in watts: positive while charging, negative on battery.
    let watts: Double?
    let timeRemainingMinutes: Int?
    /// Charge the battery was built to hold, in mAh.
    let designCapacity: Int?
    /// Charge it can hold today (full-charge capacity), in mAh.
    let maxCapacity: Int?
    /// Pack temperature in °C, straight from the battery's own gauge.
    let temperature: Double?
    /// Pack voltage in volts.
    let voltage: Double?
    /// Signed current in amps: positive charging, negative discharging.
    let amperage: Double?
    /// Apple's service condition — "Normal" or "Service Recommended".
    let condition: String

    /// Apple reports "Service Recommended" off the battery's own permanent-fault
    /// flag, not a capacity threshold — so we read the flag rather than inventing
    /// a cutoff. Pure and testable.
    static func condition(permanentFailureStatus: Int?) -> String {
        (permanentFailureStatus ?? 0) == 0 ? "Normal" : "Service Recommended"
    }
}

enum Battery {
    static func read() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any]
        else { return nil }

        func int(_ key: String) -> Int? { props[key] as? Int }
        func bool(_ key: String) -> Bool { props[key] as? Bool ?? false }

        // CurrentCapacity is a percentage on Apple Silicon, raw mAh on Intel.
        // If it's missing entirely, report no battery rather than a fabricated
        // 0% — an honest "unknown" beats a wrong reading.
        guard var percent = int("CurrentCapacity").map(Double.init) else { return nil }
        if percent > 100, let raw = int("AppleRawCurrentCapacity"), let max = int("AppleRawMaxCapacity"), max > 0 {
            percent = Double(raw) / Double(max) * 100
        }

        let design = int("DesignCapacity")
        let maxCapacity = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity")

        var health: Double?
        if let design, design > 0, let maxCapacity {
            health = Double(maxCapacity) / Double(design) * 100
        }

        let voltage = int("Voltage")
        let amperage = int("Amperage")
        var watts: Double?
        if let voltage, let amperage {
            watts = Double(voltage) * Double(amperage) / 1_000_000
        }

        // The gauge reports temperature in hundredths of a degree Celsius.
        let temperature = int("Temperature").map { Double($0) / 100 }

        var timeRemaining = int("TimeRemaining")
        if let t = timeRemaining, t <= 0 || t >= 0xFFFF { timeRemaining = nil }

        return BatterySnapshot(
            percent: min(max(percent, 0), 100),
            isCharging: bool("IsCharging"),
            externalPower: bool("ExternalConnected"),
            fullyCharged: bool("FullyCharged"),
            healthPercent: health,
            cycleCount: int("CycleCount"),
            watts: watts,
            timeRemainingMinutes: timeRemaining,
            designCapacity: design,
            maxCapacity: maxCapacity,
            temperature: temperature,
            voltage: voltage.map { Double($0) / 1000 },
            amperage: amperage.map { Double($0) / 1000 },
            condition: BatterySnapshot.condition(permanentFailureStatus: int("PermanentFailureStatus"))
        )
    }
}
