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
        var percent = Double(int("CurrentCapacity") ?? 0)
        if percent > 100, let raw = int("AppleRawCurrentCapacity"), let max = int("AppleRawMaxCapacity"), max > 0 {
            percent = Double(raw) / Double(max) * 100
        }

        var health: Double?
        if let design = int("DesignCapacity"), design > 0,
           let nominal = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") {
            health = Double(nominal) / Double(design) * 100
        }

        var watts: Double?
        if let voltage = int("Voltage"), let amperage = int("Amperage") {
            watts = Double(voltage) * Double(amperage) / 1_000_000
        }

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
            timeRemainingMinutes: timeRemaining
        )
    }
}
