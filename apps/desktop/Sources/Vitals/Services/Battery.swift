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
    /// `officialHealth`, when supplied, is macOS's own "Maximum Capacity"
    /// figure (see `BatteryHealth`). It's preferred for `healthPercent` so the
    /// app matches System Settings exactly; the raw full-charge/design ratio is
    /// only a fallback for the first moments before it's read, or if it can't be.
    static func read(officialHealth: Double? = nil) -> BatterySnapshot? {
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

        // Prefer macOS's smoothed Maximum Capacity; fall back to the raw ratio.
        // The raw register ratio (e.g. 93.98%) is a real reading but differs
        // from the figure macOS shows — that gap confuses, so we match macOS.
        var health = officialHealth
        if health == nil, let design, design > 0, let maxCapacity {
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

/// macOS's own "Maximum Capacity" figure — the exact percentage System Settings
/// → Battery shows. It's a smoothed value computed by a private framework and
/// matches no single IORegistry register (the raw full-charge/design ratio reads
/// a point or two lower), so to show what the user sees we ask macOS directly
/// via `system_profiler`. That spawns a process (~0.15 s), so it's read off the
/// main thread and cached — battery health changes over weeks, not seconds.
enum BatteryHealth {
    /// Reads and parses macOS's Maximum Capacity, or nil if unavailable (no
    /// battery, or the tool failed). Blocking — call off the main thread.
    static func maximumCapacityPercent() -> Double? {
        guard let data = runSystemProfiler() else { return nil }
        return parse(data)
    }

    /// Pulls `sppower_battery_health_maximum_capacity` ("95%") out of
    /// `system_profiler -json SPPowerDataType`. The JSON keys aren't localized,
    /// so this is locale-proof. Pure, for testing.
    static func parse(_ data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            if let info = item["sppower_battery_health_info"] as? [String: Any],
               let raw = info["sppower_battery_health_maximum_capacity"] as? String {
                let digits = raw.filter(\.isNumber)
                if let value = Double(digits), value > 0, value <= 100 { return value }
            }
        }
        return nil
    }

    private static func runSystemProfiler() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPPowerDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // SPPowerDataType output is small, so reading to EOF then waiting
            // can't deadlock on a full pipe.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }
}
