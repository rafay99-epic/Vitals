import Foundation

/// Append-only JSONL log at `DataHome.logFile`, rotated to `DataHome.logPrevious`
/// past the size cap. Best-effort: a failed write is dropped so logging never
/// throws into a caller.
///
/// All writes go through one serial queue, so `Log.emit` returns immediately.
final class LogFile {
    static let shared = LogFile()

    private static let maximumBytes: UInt64 = 5_000_000

    private let queue = DispatchQueue(label: "com.syntaxlab.vitals.logfile", qos: .utility)
    private var handle: FileHandle?
    private var writesSinceSizeCheck = 0
    private static let writesPerSizeCheck = 200

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// The JSON encode runs on the serial queue, not the calling thread.
    func append(_ entry: Log.Entry) {
        queue.async { [weak self] in
            guard let self, let line = try? Self.encoder.encode(entry) else { return }
            self.write(line)
        }
    }

    /// Blocks until this entry and everything queued before it is written. For
    /// the exception handler, where the async queue would never drain.
    func appendSync(_ entry: Log.Entry) {
        queue.sync {
            guard let line = try? Self.encoder.encode(entry) else { return }
            self.write(line)
        }
    }

    private func write(_ jsonLine: Data) {
        guard let handle = openHandleIfNeeded() else { return }
        var data = jsonLine
        data.append(0x0A)
        try? handle.write(contentsOf: data)
        writesSinceSizeCheck += 1
        if writesSinceSizeCheck >= Self.writesPerSizeCheck {
            writesSinceSizeCheck = 0
            if let size = fileSizeBytes, size > Self.maximumBytes {
                try? handle.close()
                self.handle = nil  // next write reopens and rotates
            }
        }
    }

    private var fileSizeBytes: UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: DataHome.logFile.path)[.size] as? UInt64) ?? nil
    }

    private func openHandleIfNeeded() -> FileHandle? {
        if let handle { return handle }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: DataHome.logsDirectory, withIntermediateDirectories: true)
            if let size = fileSizeBytes, size > Self.maximumBytes {
                let archived = DataHome.logPrevious
                try? fm.removeItem(at: archived)
                try fm.moveItem(at: DataHome.logFile, to: archived)
            }
            if !fm.fileExists(atPath: DataHome.logFile.path) {
                fm.createFile(atPath: DataHome.logFile.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: DataHome.logFile)
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

extension LogFile {
    /// Both log files (rotated first) as raw text, plus the decoded entries.
    /// Crash backtraces are plain text, so they're only in `raw`. Blocking.
    static func readAll() -> (raw: String, entries: [Log.Entry]) {
        let raw = [DataHome.logPrevious, DataHome.logFile]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let entries = raw.split(separator: "\n").compactMap { line in
            try? decoder.decode(Log.Entry.self, from: Data(line.utf8))
        }
        return (raw, entries)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
