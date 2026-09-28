import Foundation
import os

/// Severity, ordered low to high. The "Diagnostic logging" setting picks a floor
/// (`Log.minimumLevel`); lines below it are dropped before the message closure
/// runs, so a disabled line builds no string.
enum LogLevel: Int, CaseIterable, Comparable, Codable, Identifiable {
    case debug = 0, info, notice, error, fault
    /// Not a severity: the floor that drops everything.
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

    /// Three-letter level column in exported logs.
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

    /// The Settings choices. `info` and `fault` are log levels, not user choices.
    static let settingChoices: [LogLevel] = [.off, .error, .notice, .debug]

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

/// One `os.Logger` per category (subsystem = bundle id), so Console.app and
/// `log stream` can filter by area.
enum LogCategory: String, CaseIterable, Identifiable, Codable {
    case app, sensors, smc, fan, sampler, updater, history
    case cleanup, uninstall, settings, net

    var id: String { rawValue }

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
        case .settings:   return "Settings"
        case .net:        return "Network"
        }
    }
}

/// Thread-safe structured logger. Writes to unified logging (`os.Logger`) and to
/// the rotating JSONL file (`LogFile`) that the problem report attaches.
enum Log {
    struct Source: Codable, Equatable {
        let file: String       // just the file name, e.g. "Updater.swift"
        let function: String
        let line: Int
    }

    /// An `Error`'s domain and code, which survive localization.
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

        /// One-line tail for the os.Logger string and exports.
        var inline: String {
            var text = "\(type)(\(domain) \(code)): \(description)"
            if let underlying { text += " ← \(underlying)" }
            return text
        }
    }

    /// One captured line, persisted as JSONL by `LogFile`.
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

    /// Short per-launch id on every entry. `CrashReporter` uses it to tell runs apart.
    static let session = String(UUID().uuidString.prefix(8))

    // MARK: Configuration (thread-safe)

    private static let minimumLevel = OSAllocatedUnfairLock(initialState: LogLevel.notice)

    /// Called from `AppSettings` at launch and when the level changes.
    static func configure(minimumLevel level: LogLevel) {
        minimumLevel.withLock { $0 = level }
    }

    // MARK: Emit

    static func debug(_ category: LogCategory, _ message: @autoclosure () -> String, error: Error? = nil,
                      file: String = #fileID, function: String = #function, line: Int = #line) {
        emit(.debug, category, message(), error, file, function, line)
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

    /// Logs only the first time `key` is seen this launch, for failures that
    /// would otherwise repeat every sample tick.
    static func noticeOnce(_ category: LogCategory, key: String, _ message: @autoclosure () -> String, error: Error? = nil,
                           file: String = #fileID, function: String = #function, line: Int = #line) {
        guard firstTime(key) else { return }
        emit(.notice, category, message(), error, file, function, line)
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
        let minimum = minimumLevel.withLock { $0 }
        // Bail before building the string.
        guard minimum != .off, level >= minimum else { return }

        let text = message()
        let source = Source(file: shortName(file), function: function, line: line)
        let info = error.map(ErrorInfo.init)

        let suffix = info.map { " | \($0.inline)" } ?? ""
        loggers[category]?.log(level: level.osType, "[\(session)] \(text)\(suffix) (\(source.file):\(line))")

        let entry = Entry(id: UUID(), time: Date(), session: session, level: level,
                          category: category, message: text, source: source, error: info)
        LogFile.shared.append(entry)
    }

    /// Writes an entry synchronously, ignoring the level filter. For the crash
    /// path and the clean-shutdown marker, which must never be dropped.
    static func writeSync(_ level: LogLevel, _ category: LogCategory, _ message: String,
                          file: String = #fileID, function: String = #function, line: Int = #line) {
        let source = Source(file: shortName(file), function: function, line: line)
        loggers[category]?.log(level: level.osType, "[\(session)] \(message)")
        let entry = Entry(id: UUID(), time: Date(), session: session, level: level,
                          category: category, message: message, source: source, error: nil)
        LogFile.shared.appendSync(entry)
    }

    /// `#fileID` is "ModuleName/Dir/File.swift"; keep "File.swift".
    private static func shortName(_ fileID: String) -> String {
        String(fileID.split(separator: "/").last ?? Substring(fileID))
    }

    // MARK: Unified-logging backends

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.syntaxlab.vitals"

    /// Immutable, so no locking needed.
    private static let loggers: [LogCategory: os.Logger] = Dictionary(
        uniqueKeysWithValues: LogCategory.allCases.map { ($0, os.Logger(subsystem: subsystem, category: $0.rawValue)) }
    )
}
