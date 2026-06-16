import Foundation
import AppKit
import PrivateSensors

/// Turns "the app vanished" into a log line. Three layers:
///
///   1. **Fatal signals** (SIGSEGV, SIGABRT, SIGILL, SIGTRAP, SIGFPE, SIGBUS) —
///      including the way Swift surfaces `fatalError`/force-unwrap traps — are
///      caught by an async-signal-safe C handler (`vitals_install_crash_handlers`)
///      that appends the symbolicated backtrace to `vitals.log`, then re-raises.
///   2. **Obj-C / NSException** is caught here in Swift and written synchronously
///      as a `fault` entry (valid JSONL, so it shows in the console next launch).
///   3. **On the next launch**, `reportPreviousRunIfNeeded()` notices a crash
///      marker or a session that never logged a clean shutdown, and surfaces a
///      readable fault/notice — so the user opens Vitals, sees "last run crashed",
///      and can email the log.
///
/// Installed only from the GUI process — never the fan daemon or a CLI run.
enum CrashReporter {
    /// Sentinel written on a graceful exit; its absence for a past session means
    /// that run was killed or crashed.
    static let cleanShutdownMessage = "session ended cleanly"

    private static let signalMarker = "===== VITALS-SIGNAL-CRASH"
    private static var ackFile: URL { DataHome.crashAckFile }

    /// Arms the signal + exception handlers. Call once, early in launch (after
    /// `DataHome.prepare()` so the log directory exists).
    static func install() {
        DataHome.logFile.path.withCString { vitals_install_crash_handlers($0) }

        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "(no reason)"
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            Log.writeFaultSync(.app, "Uncaught exception \(exception.name.rawValue): \(reason)\n\(symbols)")
        }
    }

    /// Records that this run is ending on purpose, and flushes. Call from
    /// `applicationWillTerminate`.
    static func markCleanShutdown() {
        Log.notice(.app, cleanShutdownMessage)
        LogFile.shared.flush()
    }

    /// Looks at the previous run and, if it crashed or was killed, logs a fault/
    /// notice in *this* session. Blocking (reads + parses the log), so run it off
    /// the main thread at launch. Idempotent across launches: signal crashes are
    /// de-duped with an ack count, and an unclean exit is judged once (the
    /// previous session is only ever evaluated the launch after it ends).
    static func reportPreviousRunIfNeeded() {
        let combined = [DataHome.logPrevious, DataHome.logFile]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        guard !combined.isEmpty else { return }

        // 1. Fatal-signal crash (plain-text marker from the C handler).
        let total = combined.components(separatedBy: signalMarker).count - 1
        let acked = (try? String(contentsOf: ackFile, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        if total > acked {
            let name = lastSignalName(in: combined) ?? "fatal signal"
            Log.fault(.app, "Previous run crashed (\(name)). The full backtrace is in vitals.log — please send it via Report a Problem.")
            try? "\(total)".write(to: ackFile, atomically: true, encoding: .utf8)
            return  // the crash already explains the unclean exit
        }

        // 2. Unclean exit with no crash (force quit, kill -9, power loss): the
        //    previous session has lines but never logged a clean shutdown.
        if let previous = previousSession(in: combined), !previous.clean {
            Log.notice(.app, "Previous session \(previous.id) didn't exit cleanly — force quit, kill, or power loss (no crash was recorded).")
        }
    }

    // MARK: - Parsing helpers

    /// The signal named by the most recent crash marker (e.g. "SIGSEGV").
    private static func lastSignalName(in text: String) -> String? {
        guard let range = text.range(of: signalMarker, options: .backwards) else { return nil }
        let after = text[range.upperBound...].prefix(40)
        return after.split(separator: " ").first.map(String.init)
    }

    /// The most recent session that isn't the current one, and whether it logged
    /// a clean shutdown.
    private static func previousSession(in text: String) -> (id: String, clean: Bool)? {
        var order: [String] = []
        var cleanBySession: [String: Bool] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? Self.decoder.decode(Log.Entry.self, from: data) else { continue }
            if cleanBySession[entry.session] == nil {
                order.append(entry.session)
                cleanBySession[entry.session] = false
            }
            if entry.message == cleanShutdownMessage { cleanBySession[entry.session] = true }
        }
        guard let previous = order.last(where: { $0 != Log.session }) else { return nil }
        return (previous, cleanBySession[previous] ?? false)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
