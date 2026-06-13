import Foundation

/// Reads temperatures and fan speeds from `/sys/class/hwmon` — the kernel
/// interface `lm-sensors` sits on. The directory index (`hwmon0`, `hwmon1`, …)
/// is **not** stable across reboots, so chips are matched by their `name` file,
/// never by index.
///
/// Parsing is split from reading so it can be unit-tested on fixtures with no
/// hardware present.
public enum Hwmon {

    /// Classifies a sensor by its chip name and optional per-sensor label, so the
    /// dashboard can group CPU dies, GPU, storage, and battery like the macOS app.
    public static func classify(chip: String, label: String?) -> TempReading.Kind {
        let c = chip.lowercased()
        let l = (label ?? "").lowercased()
        if c.contains("coretemp") || c.contains("k10temp") || c.contains("zenpower")
            || c.contains("cpu") || l.contains("tdie") || l.contains("tctl")
            || l.contains("package") || l.contains("core") { return .cpu }
        if c.contains("amdgpu") || c.contains("nouveau") || c.contains("i915")
            || c.contains("radeon") || c.contains("xe") || l.contains("gpu") { return .gpu }
        if c.contains("nvme") || c.contains("drivetemp") || l.contains("nvme")
            || l.contains("ssd") || l.contains("composite") { return .storage }
        if c.contains("bat") || l.contains("battery") { return .battery }
        return .other
    }

    /// Parses one hwmon directory's files (filename → contents) into readings.
    /// `tempN_input` is milli-°C; `fanN_input` is RPM. A label comes from
    /// `tempN_label`/`fanN_label` when present, else a chip-derived fallback.
    public static func parse(chip: String, files: [String: String]) -> (temps: [TempReading], fans: [FanReading]) {
        var temps: [TempReading] = []
        for key in files.keys where key.hasPrefix("temp") && key.hasSuffix("_input") {
            let index = String(key.dropFirst(4).dropLast(6))
            guard let raw = files[key]?.trimmed, let milli = Double(raw) else { continue }
            let label = files["temp\(index)_label"]?.trimmed
            let kind = classify(chip: chip, label: label)
            let display = label ?? fallbackLabel(chip: chip, index: index, kind: kind)
            temps.append(TempReading(label: display, celsius: milli / 1000, kind: kind))
        }

        var fans: [FanReading] = []
        for key in files.keys where key.hasPrefix("fan") && key.hasSuffix("_input") {
            let index = String(key.dropFirst(3).dropLast(6))
            guard let raw = files[key]?.trimmed, let rpm = Int(raw) else { continue }
            let label = files["fan\(index)_label"]?.trimmed ?? "Fan \(index)"
            fans.append(FanReading(label: label, rpm: rpm))
        }

        temps.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        fans.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return (temps, fans)
    }

    private static func fallbackLabel(chip: String, index: String, kind: TempReading.Kind) -> String {
        switch kind {
        case .cpu: return "CPU \(index)"
        case .gpu: return "GPU \(index)"
        case .storage: return "Drive \(index)"
        case .battery: return "Battery"
        case .other: return "\(chip) \(index)"
        }
    }

    // MARK: - Reading

    private static let root = "/sys/class/hwmon"

    /// Walks every hwmon chip and aggregates all readings. Returns empties on a
    /// machine that exposes none (a VM, say) rather than inventing values.
    public static func read() -> (temps: [TempReading], fans: [FanReading]) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return ([], []) }

        var temps: [TempReading] = []
        var fans: [FanReading] = []
        for entry in entries {
            let dir = "\(root)/\(entry)"
            guard let chip = try? String(contentsOfFile: "\(dir)/name", encoding: .utf8).trimmed else { continue }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            var files: [String: String] = [:]
            for name in names where name.contains("_input") || name.contains("_label") {
                if let value = try? String(contentsOfFile: "\(dir)/\(name)", encoding: .utf8) {
                    files[name] = value
                }
            }
            let parsed = parse(chip: chip, files: files)
            temps.append(contentsOf: parsed.temps)
            fans.append(contentsOf: parsed.fans)
        }
        return (temps, fans)
    }
}
