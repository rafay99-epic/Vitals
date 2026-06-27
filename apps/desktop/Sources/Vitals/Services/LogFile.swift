import Foundation

/// Mirrors structured log entries to `~/.vitals/vitals.log` as JSONL (one JSON
/// object per line) so the diagnostic snapshot can attach the recent tail and a
/// crash leaves a trail on disk. An append-only, size-capped JSONL file, rotated
/// to `vitals-previous.log` when it grows past the cap. Best-effort — a failed
/// write is dropped (a diagnostic log is not
/// critical data, and we must never let logging itself throw into a caller).
///
/// All writes hop onto one serial queue, so `Log.emit` (called from any thread)
/// returns immediately and the file is only ever touched from a single place.
final class LogFile {
    static let shared = LogFile()

    private static let maximumBytes: UInt64 = 5_000_000

    private let queue = DispatchQueue(label: "com.syntaxlab.vitals.logfile", qos: .utility)
    private var handle: FileHandle?
    private var writesSinceSizeCheck = 0
    /// Re-check size every ~200 lines rather than on every write.
    private static let writesPerSizeCheck = 200

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Queues one entry for persistence. Returns at once — the JSON encode runs
    /// on the serial queue, not the (sometimes main) calling thread.
    func append(_ entry: Log.Entry) {
        queue.async { [weak self] in
            guard let self, let line = try? Self.encoder.encode(entry) else { return }
            self.write(line)
        }
    }

    /// Writes an entry and blocks until it (and anything already queued) is on
    /// disk. Used by the clean-shutdown marker and the exception handler, where
    /// the process is about to die and the async queue would never drain.
    func appendSync(_ entry: Log.Entry) {
        queue.sync {
            guard let line = try? Self.encoder.encode(entry) else { return }
            self.write(line)
        }
    }

    /// Blocks until every queued write has landed. Called before the app exits.
    func flush() {
        queue.sync {}
    }

    private func write(_ jsonLine: Data) {
        guard let handle = openHandleIfNeeded() else { return }
        var data = jsonLine
        data.append(0x0A)  // newline → JSONL
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

    /// The most recent `limit` entries, oldest→newest, read across the rotated
    /// and current files. Blocking (file read + parse), so callers run it off the
    /// main thread. Malformed lines are skipped, never fatal.
    func loadRecent(limit: Int) -> [Log.Entry] {
        var lines: [Substring] = []
        for url in [DataHome.logPrevious, DataHome.logFile] {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                lines.append(contentsOf: text.split(separator: "\n"))
            }
        }
        let tail = lines.suffix(limit)
        return tail.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? Self.decoder.decode(Log.Entry.self, from: data)
        }
    }

    deinit {
        try? handle?.close()
    }
}
