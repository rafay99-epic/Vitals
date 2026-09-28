import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot {
    let percent: Double
    let isCharging: Bool
    let externalPower: Bool
    let fullyCharged: Bool
    /// System Settings' "Maximum Capacity" when available, else full-charge/design.
    let healthPercent: Double?
    let cycleCount: Int?
    /// Signed power flow in watts: positive while charging, negative on battery.
    let watts: Double?
    let timeRemainingMinutes: Int?
    /// Charge the battery was built to hold, in mAh.
    let designCapacity: Int?
    /// Charge it can hold today (full-charge capacity), in mAh.
    let maxCapacity: Int?
    /// Pack temperature in °C.
    let temperature: Double?
    /// Pack voltage in volts.
    let voltage: Double?
    /// Signed current in amps: positive charging, negative discharging.
    let amperage: Double?
    /// "Normal" or "Service Recommended".
    let condition: String
    /// Nil on battery.
    let adapter: AdapterInfo?

    /// Apple derives "Service Recommended" from the permanent-fault flag, not a
    /// capacity threshold.
    static func condition(permanentFailureStatus: Int?) -> String {
        (permanentFailureStatus ?? 0) == 0 ? "Normal" : "Service Recommended"
    }
}

/// The attached power adapter, from `AppleSmartBattery`'s `AdapterDetails`.
struct AdapterInfo {
    /// Rated wattage (`AdapterDetails["Watts"]`).
    let watts: Int?
    /// Negotiated voltage in volts.
    let voltage: Double?
    /// Negotiated current in amps.
    let amperage: Double?
    /// Live delivered power (negotiated V × A).
    let deliveredWatts: Double?
    let name: String?
    let isWireless: Bool

    /// Nil when no adapter is attached. Chargers report different subsets of
    /// keys, so every field is optional.
    static func parse(from details: [String: Any]?) -> AdapterInfo? {
        guard let details, !details.isEmpty else { return nil }
        let watts = details["Watts"] as? Int
        let milliVolts = details["Voltage"] as? Int
        let milliAmps = details["Current"] as? Int
        // On battery macOS still leaves a stub dict like {"FamilyCode": 0}.
        // Require a real power figure before treating a charger as attached.
        guard watts != nil || milliVolts != nil || milliAmps != nil else { return nil }
        var delivered: Double?
        if let milliVolts, let milliAmps {
            delivered = Double(milliVolts) * Double(milliAmps) / 1_000_000
        }
        let rawName = (details["Name"] as? String) ?? (details["Description"] as? String)
        return AdapterInfo(
            watts: watts,
            voltage: milliVolts.map { Double($0) / 1000 },
            amperage: milliAmps.map { Double($0) / 1000 },
            deliveredWatts: delivered,
            name: (rawName?.isEmpty == false) ? rawName : nil,
            isWireless: details["IsWireless"] as? Bool ?? false
        )
    }
}

enum Battery {
    /// Looked up once and kept for the process lifetime (0 on a desktop).
    private static let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))

    /// `officialHealth` is macOS's "Maximum Capacity" (see `BatteryHealth`),
    /// preferred so the app matches System Settings. The raw full-charge/design
    /// ratio is the fallback until it's read.
    static func read(officialHealth: Double? = nil) -> BatterySnapshot? {
        guard service != 0 else { return nil }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any]
        else { return nil }

        func int(_ key: String) -> Int? { props[key] as? Int }
        func bool(_ key: String) -> Bool { props[key] as? Bool ?? false }

        // CurrentCapacity is a percentage on Apple Silicon, raw mAh on Intel.
        // Missing entirely means no battery, not 0%.
        guard var percent = int("CurrentCapacity").map(Double.init) else { return nil }
        if percent > 100, let raw = int("AppleRawCurrentCapacity"), let max = int("AppleRawMaxCapacity"), max > 0 {
            percent = Double(raw) / Double(max) * 100
        }

        let design = int("DesignCapacity")
        let maxCapacity = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity")

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

        // Hundredths of a degree Celsius.
        let temperature = int("Temperature").map { Double($0) / 100 }

        // Same estimate the menu bar shows. Negative sentinels: -1 "still
        // calculating", -2 "unlimited / on AC". Both mean no estimate.
        let estimate = IOPSGetTimeRemainingEstimate()
        let timeRemaining = estimate > 0 ? Int(estimate / 60) : nil

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
            condition: BatterySnapshot.condition(permanentFailureStatus: int("PermanentFailureStatus")),
            adapter: AdapterInfo.parse(from: props["AdapterDetails"] as? [String: Any])
        )
    }
}

/// System Settings' "Maximum Capacity". It's smoothed by a private framework and
/// matches no IORegistry register (the raw ratio reads a point or two lower), so
/// it comes from `system_profiler`. That spawns a process (~0.15 s): read it off
/// the main thread and cache it (the sampler does).
enum BatteryHealth {
    /// Nil if there's no battery or the tool failed. Blocking.
    static func maximumCapacityPercent() -> Double? {
        guard let data = runSystemProfiler() else { return nil }
        return parse(data)
    }

    /// Parses `sppower_battery_health_maximum_capacity` ("95%"). The JSON keys
    /// aren't localized.
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
            Log.notice(.sensors, "battery: data process failed to launch", error: error)
            return nil
        }
    }
}
