import Foundation
import AppKit
import PrivateSensors

/// Turns "the app vanished" into a log line. Three layers:
///
///   1. Fatal signals (including Swift traps) are caught by an async-signal-safe
///      C handler (`vitals_install_crash_handlers`) that appends the backtrace to
///      `vitals.log`, then re-raises.
///   2. Uncaught NSExceptions are written synchronously as a `fault` entry.
///   3. On the next launch, `reportPreviousRunIfNeeded()` logs a fault/notice if
///      it finds a crash marker or a session with no clean-shutdown line.
///
/// Installed only from the GUI process, never the `--fan-daemon` path or a CLI run.
enum CrashReporter {
    /// Logged on a graceful exit; a past session without it was killed or crashed.
    static let cleanShutdownMessage = "session ended cleanly"

    private static let signalMarker = "===== VITALS-SIGNAL-CRASH"
    private static var ackFile: URL { DataHome.crashAckFile }

    /// Call once, early in launch, after `DataHome.prepare()` so the log directory exists.
    static func install() {
        DataHome.logFile.path.withCString { vitals_install_crash_handlers($0) }

        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "(no reason)"
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            Log.writeSync(.fault, .app, "Uncaught exception \(exception.name.rawValue): \(reason)\n\(symbols)")
        }
    }

    /// Call from `applicationWillTerminate`.
    static func markCleanShutdown() {
        // Bypasses the level filter: the next launch reads this marker to tell a
        // clean quit from a crash, whatever the user's log level.
        Log.writeSync(.notice, .app, cleanShutdownMessage)
    }

    /// Blocking (reads and parses the log), so run it off the main thread.
    /// Signal crashes are de-duped with an ack count so each is reported once.
    static func reportPreviousRunIfNeeded() {
        let (combined, entries) = LogFile.readAll()
        guard !combined.isEmpty else { return }

        // Fatal-signal crash: plain-text marker from the C handler.
        let total = combined.components(separatedBy: signalMarker).count - 1
        let acked = (try? String(contentsOf: ackFile, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        if total > acked {
            let name = lastSignalName(in: combined) ?? "fatal signal"
            Log.fault(.app, "Previous run crashed (\(name)). The full backtrace is in vitals.log — please send it via Report a Problem.")
            try? "\(total)".write(to: ackFile, atomically: true, encoding: .utf8)
            return  // the crash already explains the unclean exit
        }

        // Unclean exit with no crash (force quit, kill -9, power loss).
        if let previous = previousSession(in: entries), !previous.clean {
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

    /// Most recent session other than the current one.
    private static func previousSession(in entries: [Log.Entry]) -> (id: String, clean: Bool)? {
        var order: [String] = []
        var cleanBySession: [String: Bool] = [:]
        for entry in entries {
            if cleanBySession[entry.session] == nil {
                order.append(entry.session)
                cleanBySession[entry.session] = false
            }
            if entry.message == cleanShutdownMessage { cleanBySession[entry.session] = true }
        }
        guard let previous = order.last(where: { $0 != Log.session }) else { return nil }
        return (previous, cleanBySession[previous] ?? false)
    }

}
