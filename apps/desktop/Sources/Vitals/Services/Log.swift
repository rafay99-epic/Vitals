import Foundation
import os

/// Severity, ordered low→high. The user's "Diagnostic logging" setting picks a
/// floor (`Log.minimumLevel`); anything below it is dropped *before* its message
/// closure runs, so a disabled log line costs nothing — no string is built and
/// `os_log` is never called.
enum LogLevel: Int, CaseIterable, Comparable, Codable, Identifiable {
    case debug = 0, info, notice, error, fault
    /// Not a real severity — the silent floor. Selecting it drops everything.
    case off

    var id: Int { rawValue }
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Maps onto Apple's unified-logging type so Console.app colours match.
    var osType: OSLogType {
        switch self {
        case .debug:  return .debug
        case .info:   return .info
        case .notice: return .default
        case .error:  return .error
        case .fault:  return .fault
        case .off:    return .default
        }
    }

    /// Full word, for the log console rows.
    var label: String {
        switch self {
        case .debug:  return "Debug"
        case .info:   return "Info"
        case .notice: return "Notice"
        case .error:  return "Error"
        case .fault:  return "Fault"
        case .off:    return "Off"
        }
    }

    /// Three-letter badge for the console's compact level column.
    var badge: String {
        switch self {
        case .debug:  return "DBG"
        case .info:   return "INF"
        case .notice: return "NTC"
        case .error:  return "ERR"
        case .fault:  return "FLT"
        case .off:    return "OFF"
        }
    }

    /// The four stops offered in Settings (the in-between `info`/`fault` levels
    /// exist for code to log at, but aren't separate user choices).
    static let settingChoices: [LogLevel] = [.off, .error, .notice, .debug]

    /// Friendly label for the Settings picker.
    var settingLabel: String {
        switch self {
        case .off:    return "Off"
        case .error:  return "Errors"
        case .notice: return "Normal"
        case .debug:  return "Verbose"
        default:      return label
        }
    }
}

/// The subsystem a log line comes from. One `os.Logger` is created per category
/// (subsystem = the app's bundle id), so Console.app and `log stream
/// --predicate 'subsystem == "…vitals"'` can filter by area.
enum LogCategory: String, CaseIterable, Identifiable, Codable {
    case app, sensors, smc, fan, sampler, updater, history
    case cleanup, uninstall, storage, processes, widgets, settings, net

    var id: String { rawValue }

    /// Pretty name for the console's category chip / filter menu.
    var title: String {
        switch self {
        case .app:        return "App"
        case .sensors:    return "Sensors"
        case .smc:        return "SMC"
        case .fan:        return "Fan"
        case .sampler:    return "Sampler"
        case .updater:    return "Updater"
        case .history:    return "History"
        case .cleanup:    return "Cleanup"
        case .uninstall:  return "Uninstall"
        case .storage:    return "Storage"
        case .processes:  return "Processes"
        case .widgets:    return "Widgets"
        case .settings:   return "Settings"
        case .net:        return "Network"
        }
    }
}

/// The app's structured logger. Deliberately a free `enum` of statics, not an
/// injected object: hardware services live far from the UI and any of them — on
/// any thread, even the root fan daemon in its own process — can call
/// `Log.error(.smc, "…")` without plumbing a dependency through. It writes to
/// three places, cheapest first:
///   1. **Unified logging** (`os.Logger`) — always, when the level passes. Near
///      free, integrates with Console.app and the `log` CLI.
///   2. **A rotating file** (`LogFile`, `~/.vitals/vitals.log`) so the
///      problem-report flow can attach the recent tail with no extra tooling.
///   3. **An in-memory sink** (set by `LogStore`) that feeds the in-app console.
///
/// Honesty over decoration applies to errors too: a swallowed failure leaves no
/// trace, so the services route their `catch`/`try?` failures here instead.
///
/// Every entry is **structured**: a per-launch `session` id (so one run's lines
/// group together in a shared report), the originating `source` (file/function/
/// line, captured automatically), and — when an `Error` is passed — its type,
/// domain, code and underlying cause. The whole entry is `Codable`, persisted as
/// one JSON object per line.
enum Log {
    /// Where a line came from, captured automatically from the call site.
    struct Source: Codable, Equatable {
        let file: String       // just the file name, e.g. "Updater.swift"
        let function: String
        let line: Int
    }

    /// A failure's machine-readable details, extracted from any `Error`. This is
    /// the difference between "junior" logging (a localized sentence) and a real
    /// record: the domain + code survive localisation and pinpoint the failure.
    struct ErrorInfo: Codable, Equatable {
        let type: String        // the Swift type, e.g. "URLError"
        let domain: String      // NSError domain
        let code: Int           // NSError code
        let description: String  // localizedDescription
        let underlying: String?  // the chained NSUnderlyingError, if any

        init(_ error: Error) {
            let ns = error as NSError
            type = String(describing: Swift.type(of: error))
            domain = ns.domain
            code = ns.code
            description = error.localizedDescription
            if let cause = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                underlying = "\(cause.localizedDescription) [\(cause.domain) \(cause.code)]"
            } else {
                underlying = nil
            }
        }

        /// One-line tail for the os.Logger string and console rows.
        var inline: String {
            var text = "\(type)(\(domain) \(code)): \(description)"
            if let underlying { text += " ← \(underlying)" }
            return text
        }
    }

    /// One captured line. `Codable` so `LogFile` can persist it as JSONL and the
    /// console can read it back.
    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let time: Date
        let session: String
        let level: LogLevel
        let category: LogCategory
        let message: String
        let source: Source
        let error: ErrorInfo?
    }

    /// A short id for this process launch. Every entry carries it, so when a user
    /// emails their log it's obvious which lines belong to the run that went
    /// wrong — and the previous-run crash check can tell sessions apart.
    static let session = String(UUID().uuidString.prefix(8))

    // MARK: Configuration (thread-safe)

    private struct State {
        var minimumLevel: LogLevel = .notice
        var sink: ((Entry) -> Void)?
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Sets the capture floor. Called from `AppSettings` whenever the user
    /// changes the "Diagnostic logging" level (and once at launch).
    static func configure(minimumLevel: LogLevel) {
        state.withLock { $0.minimumLevel = minimumLevel }
    }

    /// The current capture floor — lets hot-path callers skip work entirely.
    static var minimumLevel: LogLevel { state.withLock { $0.minimumLevel } }

    /// Registers (or clears) the live in-memory consumer — `LogStore` plugs the
    /// console in here. Held weakly by the closure the caller passes.
    static func setSink(_ sink: ((Entry) -> Void)?) {
        state.withLock { $0.sink = sink }
    }

    // MARK: Emit

    static func debug(_ category: LogCategory, _ message: @autoclosure () -> String, error: Error? = nil,
                      file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.debug, category, message(), error, file, function, line)
    }
    static func info(_ category: LogCategory, _ message: @autoclosure () -> String, error: Error? = nil,
                     file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.info, category, message(), error, file, function, line)
    }
    static func notice(_ category: LogCategory, _ message: @autoclosure () -> String, error: Error? = nil,
                       file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.notice, category, message(), error, file, function, line)
    }
    static func error(_ category: LogCategory, _ message: @autoclosure () -> String, error: Error? = nil,
                      file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.error, category, message(), error, file, function, line)
    }
    static func fault(_ category: LogCategory, _ message: @autoclosure () -> String, error: Error? = nil,
                      file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.fault, category, message(), error, file, function, line)
    }

    // MARK: Emit once (hot-path)

    /// Logs only the first time a given `key` is seen this launch. For failures
    /// that recur every sample tick (a missing sensor subsystem, the fan daemon's
    /// apply loop) — the first occurrence explains the symptom; the next thousand
    /// would just flood. Same call site, captured automatically.
    static func noticeOnce(_ category: LogCategory, key: String, _ message: @autoclosure () -> String, error: Error? = nil,
                           file: String = #fileID, function: String = #function, line: Int = #line) {
        guard firstTime(key) else { return }
        emit(.notice, category, message(), error, file, function, line)
    }
    static func debugOnce(_ category: LogCategory, key: String, _ message: @autoclosure () -> String, error: Error? = nil,
                          file: String = #fileID, function: String = #function, line: Int = #line) {
        guard firstTime(key) else { return }
        emit(.debug, category, message(), error, file, function, line)
    }
    static func errorOnce(_ category: LogCategory, key: String, _ message: @autoclosure () -> String, error: Error? = nil,
                          file: String = #fileID, function: String = #function, line: Int = #line) {
        guard firstTime(key) else { return }
        emit(.error, category, message(), error, file, function, line)
    }

    private static let firedKeys = OSAllocatedUnfairLock(initialState: Set<String>())
    private static func firstTime(_ key: String) -> Bool {
        firedKeys.withLock { keys in
            guard !keys.contains(key) else { return false }
            keys.insert(key)
            return true
        }
    }

    private static func emit(_ level: LogLevel, _ category: LogCategory, _ message: @autoclosure () -> String,
                             _ error: Error?, _ file: String, _ function: String, _ line: Int) {
        let (minimum, sink) = state.withLock { ($0.minimumLevel, $0.sink) }
        // The whole point of the level guard: bail before building the string.
        guard minimum != .off, level >= minimum else { return }

        let text = message()
        let source = Source(file: shortName(file), function: function, line: line)
        let info = error.map(ErrorInfo.init)

        let suffix = info.map { " | \($0.inline)" } ?? ""
        loggers[category]?.log(level: level.osType, "[\(session)] \(text)\(suffix) (\(source.file):\(line))")

        let entry = Entry(id: UUID(), time: Date(), session: session, level: level,
                          category: category, message: text, source: source, error: info)
        LogFile.shared.append(entry)
        sink?(entry)
    }

    /// Force-writes a fault entry **synchronously**, bypassing the level filter —
    /// for the crash path, where the process is about to die so nothing may be
    /// dropped and the async file queue would never drain. See `CrashReporter`.
    static func writeFaultSync(_ category: LogCategory, _ message: String,
                               file: String = #fileID, function: String = #function, line: Int = #line) {
        let source = Source(file: shortName(file), function: function, line: line)
        loggers[category]?.log(level: .fault, "[\(session)] \(message)")
        let entry = Entry(id: UUID(), time: Date(), session: session, level: .fault,
                          category: category, message: message, source: source, error: nil)
        LogFile.shared.appendSync(entry)
        state.withLock { $0.sink }?(entry)
    }

    /// `#fileID` is "ModuleName/Dir/File.swift"; we only want "File.swift".
    private static func shortName(_ fileID: String) -> String {
        String(fileID.split(separator: "/").last ?? Substring(fileID))
    }

    // MARK: Unified-logging backends

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.syntaxlab.vitals"

    /// One immutable `os.Logger` per category, built once. `os.Logger` is itself
    /// a thin handle, so this is cheap and needs no locking.
    private static let loggers: [LogCategory: os.Logger] = Dictionary(
        uniqueKeysWithValues: LogCategory.allCases.map { ($0, os.Logger(subsystem: subsystem, category: $0.rawValue)) }
    )
}
