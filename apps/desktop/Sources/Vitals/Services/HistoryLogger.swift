import Foundation

/// Appends readings to a CSV file in the Vitals data home (`DataHome`) so
/// temperature trends survive restarts. Writes at most one line every 10
/// seconds (~5 MB per month of continuous running).
final class HistoryLogger {
    static var directory: URL { DataHome.directory }
    static var fileURL: URL { DataHome.historyFile }

    private static let header = "timestamp,avg_cpu_temp_c,hottest_cpu_temp_c,gpu_temp_c,fan_rpm,cpu_usage_pct,memory_used_gb,thermal_state,battery_pct,gpu_usage_pct,gpu_mem_used_gb\n"
    private static let minimumInterval: TimeInterval = 10
    private static let maximumBytes: UInt64 = 50_000_000

    private var handle: FileHandle?
    private var lastWrite: Date = .distantPast
    private var writesSinceSizeCheck = 0
    /// Rotation happens when the handle is opened; re-check hourly (one
    /// write per 10 s) so a months-long run can't grow past the cap.
    private static let writesPerSizeCheck = 360

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// One row of readings to log. Bundled into a struct so `append` takes a
    /// single argument (and stays under the lint parameter-count limit).
    struct Entry {
        let averageTemp: Double
        let hottestTemp: Double
        let gpuTemp: Double?
        let fanRPM: Double?
        let cpuUsage: Double
        let memoryUsedGB: Double
        let thermalState: String
        let batteryPercent: Double?
        let gpuUsage: Double?
        let gpuMemoryGB: Double?
    }

    func append(_ entry: Entry) {
        let now = Date()
        guard now.timeIntervalSince(lastWrite) >= Self.minimumInterval else { return }
        guard let handle = openHandleIfNeeded() else { return }

        let fields: [String] = [
            Self.timestampFormatter.string(from: now),
            String(format: "%.1f", entry.averageTemp),
            String(format: "%.1f", entry.hottestTemp),
            entry.gpuTemp.map { String(format: "%.1f", $0) } ?? "",
            entry.fanRPM.map { String(format: "%.0f", $0) } ?? "",
            String(format: "%.1f", entry.cpuUsage),
            String(format: "%.2f", entry.memoryUsedGB),
            entry.thermalState,
            entry.batteryPercent.map { String(format: "%.0f", $0) } ?? "",
            entry.gpuUsage.map { String(format: "%.1f", $0) } ?? "",
            entry.gpuMemoryGB.map { String(format: "%.2f", $0) } ?? "",
        ]
        if let data = (fields.joined(separator: ",") + "\n").data(using: .utf8) {
            try? handle.write(contentsOf: data)
            lastWrite = now
            writesSinceSizeCheck += 1
            if writesSinceSizeCheck >= Self.writesPerSizeCheck {
                writesSinceSizeCheck = 0
                if let size = fileSizeBytes, size > Self.maximumBytes {
                    try? handle.close()
                    self.handle = nil  // next append reopens and rotates
                }
            }
        }
    }

    var fileSizeBytes: UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path)[.size] as? UInt64) ?? nil
    }

    private func openHandleIfNeeded() -> FileHandle? {
        if let handle { return handle }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            if let size = fileSizeBytes, size > Self.maximumBytes {
                let archived = DataHome.historyPrevious
                try? fm.removeItem(at: archived)
                try fm.moveItem(at: Self.fileURL, to: archived)
            }
            if !fm.fileExists(atPath: Self.fileURL.path) {
                try Self.header.data(using: .utf8)!.write(to: Self.fileURL)
            }
            let handle = try FileHandle(forWritingTo: Self.fileURL)
            try handle.seekToEnd()
            self.handle = handle
            return handle
        } catch {
            Log.error(.history, "couldn't open history log for writing", error: error)
            return nil
        }
    }

    deinit {
        try? handle?.close()
    }
}
