import Foundation

/// Battery and AC state from `/sys/class/power_supply`. A machine with no
/// battery (a desktop) yields `nil`, never a fabricated 100%.
public enum PowerSupply {

    /// Builds a snapshot from one battery directory's files (filename → contents)
    /// and the AC `online` flag. Energy units in sysfs are µWh/µW; charge units
    /// are µAh/µA; voltage is µV.
    public static func parseBattery(files: [String: String], acOnline: Bool?) -> BatterySnapshot? {
        func string(_ key: String) -> String? { files[key]?.trimmed }
        func int(_ key: String) -> Int? { string(key).flatMap { Int($0) } }
        func double(_ key: String) -> Double? { string(key).flatMap { Double($0) } }

        guard let percent = double("capacity") else { return nil }
        let status = string("status") ?? "Unknown"

        // Health: present full-charge capacity vs. design. Works whether the
        // gauge reports energy (µWh) or charge (µAh).
        var health: Double?
        if let full = double("energy_full"), let design = double("energy_full_design"), design > 0 {
            health = full / design * 100
        } else if let full = double("charge_full"), let design = double("charge_full_design"), design > 0 {
            health = full / design * 100
        }

        // Power flow in watts, signed negative while discharging. Prefer the
        // direct power reading; otherwise derive it from current × voltage.
        var watts: Double?
        if let power = double("power_now") {
            watts = power / 1_000_000
        } else if let current = double("current_now"), let voltage = double("voltage_now") {
            watts = current * voltage / 1_000_000_000_000
        }
        if status == "Discharging", let w = watts { watts = -abs(w) }
        if status == "Charging", let w = watts { watts = abs(w) }

        return BatterySnapshot(
            percent: min(max(percent, 0), 100),
            status: status,
            isCharging: status == "Charging",
            onACPower: acOnline ?? (status != "Discharging"),
            healthPercent: health,
            cycleCount: int("cycle_count"),
            watts: watts
        )
    }

    private static let root = "/sys/class/power_supply"

    public static func read() -> BatterySnapshot? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return nil }

        // AC adapter: the first "Mains" supply that's online.
        var acOnline: Bool?
        for entry in entries {
            let dir = "\(root)/\(entry)"
            let type = (try? String(contentsOfFile: "\(dir)/type", encoding: .utf8).trimmed) ?? ""
            if type == "Mains", let online = try? String(contentsOfFile: "\(dir)/online", encoding: .utf8).trimmed {
                acOnline = online == "1"
            }
        }

        for entry in entries {
            let dir = "\(root)/\(entry)"
            let type = (try? String(contentsOfFile: "\(dir)/type", encoding: .utf8).trimmed) ?? ""
            guard type == "Battery" else { continue }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            var files: [String: String] = [:]
            for name in names {
                if let value = try? String(contentsOfFile: "\(dir)/\(name)", encoding: .utf8) {
                    files[name] = value
                }
            }
            if let snapshot = parseBattery(files: files, acOnline: acOnline) { return snapshot }
        }
        return nil
    }
}
