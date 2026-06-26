import Foundation

/// One row of logged history — a database row, or a parsed legacy CSV line
/// during import. Mirrors `HistoryDatabase.Entry`. Optionals are readings that
/// weren't available when the row was written (a subsystem that wasn't present).
struct HistorySample: Identifiable, Codable {
    let time: Date
    let avgTemp: Double
    let hottestTemp: Double
    let gpuTemp: Double?
    let fanRPM: Double?
    let cpuUsage: Double
    let memoryGB: Double
    let thermalState: String
    let batteryPercent: Double?
    let gpuUsage: Double?
    let gpuMemoryGB: Double?
    var id: Date { time }
}

/// Time windows the History tab can zoom to.
enum HistoryRange: String, CaseIterable, Identifiable {
    case hour, day, week, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: return "Hour"
        case .day:  return "Day"
        case .week: return "Week"
        case .all:  return "All"
        }
    }

    /// Window length, or nil for "everything logged".
    var seconds: TimeInterval? {
        switch self {
        case .hour: return 3600
        case .day:  return 86_400
        case .week: return 604_800
        case .all:  return nil
        }
    }
}

/// Reads logged history back into samples for the History tab. Blocking (a SQLite
/// range query), so it's always called off the main thread; the view shows a
/// loading state meanwhile and only reads while the tab is open — so it costs
/// nothing in the background. The actual storage is `HistoryDatabase`; this stays
/// the view-facing API (and still owns the CSV `parse` used by the one-time import).
enum HistoryReader {
    /// Loads samples within `range`, oldest→newest, downsampled to `maxPoints`
    /// for drawing. The database returns a coarse-thinned set; this applies the
    /// final exact down-sample (keeping first + last).
    static func load(range: HistoryRange, now: Date, maxPoints: Int = 600) -> [HistorySample] {
        let raw = HistoryDatabase.shared.samples(range: range, now: now, maxPoints: maxPoints)
        return downsample(raw, to: maxPoints)
    }

    /// Parses one legacy CSV row. Returns nil for the header and any malformed
    /// line, so those are skipped. Used by `HistoryDatabase`'s one-time CSV import.
    static func parse(_ line: Substring) -> HistorySample? {
        let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 11,
              let time = isoFormatter.date(from: f[0]),
              let avg = Double(f[1]), let hottest = Double(f[2]),
              let cpu = Double(f[5]), let mem = Double(f[6])
        else { return nil }
        func optional(_ value: String) -> Double? { value.isEmpty ? nil : Double(value) }
        return HistorySample(
            time: time, avgTemp: avg, hottestTemp: hottest,
            gpuTemp: optional(f[3]), fanRPM: optional(f[4]),
            cpuUsage: cpu, memoryGB: mem, thermalState: f[7],
            batteryPercent: optional(f[8]), gpuUsage: optional(f[9]), gpuMemoryGB: optional(f[10])
        )
    }

    /// Even thinning to at most `maxCount`, keeping first and last.
    private static func downsample(_ samples: [HistorySample], to maxCount: Int) -> [HistorySample] {
        guard samples.count > maxCount, maxCount > 1 else { return samples }
        let stride = Double(samples.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { samples[Int((Double($0) * stride).rounded())] }
    }

    /// Shared with `HistoryExport` so an exported CSV matches the legacy column
    /// format exactly (and round-trips through `parse`).
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Writes the logged history into the data home's `exports/` folder. Blocking
/// (queries/encodes the whole log), so it's called off the main thread.
enum HistoryExport {
    /// The CSV header — the legacy column order, kept stable so exports stay
    /// readable by the same tools and round-trip through `HistoryReader.parse`.
    static let csvHeader = "timestamp,avg_cpu_temp_c,hottest_cpu_temp_c,gpu_temp_c,fan_rpm,cpu_usage_pct,memory_used_gb,thermal_state,battery_pct,gpu_usage_pct,gpu_mem_used_gb\n"

    /// Writes the whole database out as CSV (every row, no down-sampling); returns
    /// the new file, or nil if there's nothing logged yet.
    static func csv() -> URL? {
        let samples = HistoryReader.load(range: .all, now: Date(), maxPoints: .max)
        guard !samples.isEmpty else { return nil }
        guard let destination = prepareDestination(extension: "csv") else { return nil }
        var text = csvHeader
        for sample in samples { text += csvLine(sample) }
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        } catch {
            Log.notice(.history, "history CSV export failed", error: error)
            return nil
        }
    }

    /// One CSV row in the legacy format/precision (so round-trips with `parse`).
    private static func csvLine(_ s: HistorySample) -> String {
        let fields: [String] = [
            HistoryReader.isoFormatter.string(from: s.time),
            String(format: "%.1f", s.avgTemp),
            String(format: "%.1f", s.hottestTemp),
            s.gpuTemp.map { String(format: "%.1f", $0) } ?? "",
            s.fanRPM.map { String(format: "%.0f", $0) } ?? "",
            String(format: "%.1f", s.cpuUsage),
            String(format: "%.2f", s.memoryGB),
            s.thermalState,
            s.batteryPercent.map { String(format: "%.0f", $0) } ?? "",
            s.gpuUsage.map { String(format: "%.1f", $0) } ?? "",
            s.gpuMemoryGB.map { String(format: "%.2f", $0) } ?? "",
        ]
        return fields.joined(separator: ",") + "\n"
    }

    /// Parses the whole log and writes it as a JSON array; nil if empty.
    static func json() -> URL? {
        let samples = HistoryReader.load(range: .all, now: Date(), maxPoints: .max)
        guard !samples.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let destination = prepareDestination(extension: "json") else { return nil }
        do {
            try encoder.encode(samples).write(to: destination)
            return destination
        } catch {
            Log.notice(.history, "history JSON export failed", error: error)
            return nil
        }
    }

    private static func prepareDestination(extension ext: String) -> URL? {
        try? FileManager.default.createDirectory(at: DataHome.exportsDirectory, withIntermediateDirectories: true)
        let stamp = stampFormatter.string(from: Date())
        return DataHome.exportsDirectory.appendingPathComponent("vitals-history-\(stamp).\(ext)")
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
