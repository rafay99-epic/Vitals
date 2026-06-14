import Foundation

/// Appends readings to a CSV file in Application Support so temperature
/// trends survive restarts. Writes at most one line every 10 seconds
/// (~5 MB per month of continuous running).
final class HistoryLogger {
    static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Vitals", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("history.csv")

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

    func append(
        averageTemp: Double,
        hottestTemp: Double,
        gpuTemp: Double?,
        fanRPM: Double?,
        cpuUsage: Double,
        memoryUsedGB: Double,
        thermalState: String,
        batteryPercent: Double?,
        gpuUsage: Double?,
        gpuMemoryGB: Double?
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastWrite) >= Self.minimumInterval else { return }
        guard let handle = openHandleIfNeeded() else { return }

        let fields: [String] = [
            Self.timestampFormatter.string(from: now),
            String(format: "%.1f", averageTemp),
            String(format: "%.1f", hottestTemp),
            gpuTemp.map { String(format: "%.1f", $0) } ?? "",
            fanRPM.map { String(format: "%.0f", $0) } ?? "",
            String(format: "%.1f", cpuUsage),
            String(format: "%.2f", memoryUsedGB),
            thermalState,
            batteryPercent.map { String(format: "%.0f", $0) } ?? "",
            gpuUsage.map { String(format: "%.1f", $0) } ?? "",
            gpuMemoryGB.map { String(format: "%.2f", $0) } ?? "",
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
                let archived = Self.directory.appendingPathComponent("history-previous.csv")
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
            return nil
        }
    }

    deinit {
        try? handle?.close()
    }
}
