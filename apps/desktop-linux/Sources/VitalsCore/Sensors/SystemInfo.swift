import Foundation

/// The CPU's marketing name from `/proc/cpuinfo`.
public enum CPUInfo {

    /// Returns the first usable name. x86 reports `model name`; ARM boards often
    /// only have `Hardware` or `Processor`. Returns nil if none are present, so
    /// the UI can fall back to a generic label rather than show a blank.
    public static func parseModelName(_ content: String) -> String? {
        let keys = ["model name", "Hardware", "Processor", "cpu model"]
        for key in keys {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmed == key else { continue }
                let value = parts[1].trimmed
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    public static func read(path: String = "/proc/cpuinfo") -> String? {
        (try? String(contentsOfFile: path, encoding: .utf8)).flatMap(parseModelName)
    }
}

/// Thermal-zone temperatures (`/sys/class/thermal/thermal_zoneN`). Used only as
/// a fallback when hwmon exposes no temperatures (some ARM/VM systems), since
/// zones and hwmon often surface the same sensors twice.
public enum ThermalZones {

    private static let root = "/sys/class/thermal"

    public static func read() -> [TempReading] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return [] }

        var temps: [TempReading] = []
        for entry in entries where entry.hasPrefix("thermal_zone") {
            let dir = "\(root)/\(entry)"
            guard let rawTemp = try? String(contentsOfFile: "\(dir)/temp", encoding: .utf8).trimmed,
                  let milli = Double(rawTemp) else { continue }
            let type = (try? String(contentsOfFile: "\(dir)/type", encoding: .utf8).trimmed) ?? entry
            let kind = Hwmon.classify(chip: type, label: nil)
            temps.append(TempReading(label: type, celsius: milli / 1000, kind: kind))
        }
        return temps
    }
}
