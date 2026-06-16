import Foundation

/// One parsed row from the history log. Mirrors `HistoryLogger.Entry` /
/// `HistoryLogger.header`. Optionals are columns that were blank (a subsystem
/// that wasn't present when the row was written).
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

/// Reads the logged history CSV back into samples for the History tab. Blocking
/// (file read + parse), so it's always called off the main thread; the view
/// shows a loading state meanwhile and only reads while the tab is open — so it
/// costs nothing in the background.
enum HistoryReader {
    /// Loads samples within `range`, oldest→newest, downsampled to `maxPoints`
    /// for drawing. For short ranges it walks the file from the newest line and
    /// stops at the cutoff, so it never parses old rows it won't show.
    static func load(range: HistoryRange, now: Date, maxPoints: Int = 600) -> [HistorySample] {
        // The rotated previous file only matters for the long ranges.
        let files: [URL] = (range == .week || range == .all)
            ? [DataHome.historyPrevious, DataHome.historyFile]
            : [DataHome.historyFile]

        var lines: [Substring] = []
        for url in files {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                lines.append(contentsOf: text.split(separator: "\n"))
            }
        }

        var samples: [HistorySample] = []
        if let seconds = range.seconds {
            let cutoff = now.addingTimeInterval(-seconds)
            for line in lines.reversed() {
                guard let sample = parse(line) else { continue }
                if sample.time < cutoff { break }
                samples.append(sample)
            }
            samples.reverse()
        } else {
            for line in lines where !line.isEmpty {
                if let sample = parse(line) { samples.append(sample) }
            }
        }
        return downsample(samples, to: maxPoints)
    }

    /// Parses one CSV row. Returns nil for the header and any malformed line, so
    /// those are skipped rather than crashing the read.
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

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Writes the logged history into the data home's `exports/` folder. Blocking
/// (reads/encodes the whole log), so it's called off the main thread.
enum HistoryExport {
    /// Copies the full CSV log; returns the new file, or nil if there's nothing yet.
    static func csv() -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: DataHome.historyFile.path) else { return nil }
        guard let destination = prepareDestination(extension: "csv") else { return nil }
        try? fm.removeItem(at: destination)
        do {
            try fm.copyItem(at: DataHome.historyFile, to: destination)
            return destination
        } catch {
            Log.notice(.history, "history CSV export failed", error: error)
            return nil
        }
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
