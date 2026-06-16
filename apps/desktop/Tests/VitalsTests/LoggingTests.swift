import Testing
import Foundation
@testable import Vitals

/// Locks the structured-logging contract: severity ordering, the error-detail
/// extraction that makes a log line diagnosable (domain/code/underlying), and
/// the date grouping the console + shared report rely on.
struct LoggingTests {
    @Test func levelsOrderBySeverity() {
        #expect(LogLevel.debug < LogLevel.notice)
        #expect(LogLevel.notice < LogLevel.error)
        #expect(LogLevel.error < LogLevel.fault)
        // `off` is the highest stop, so "level >= off" is never true — nothing logs.
        #expect(LogLevel.fault < LogLevel.off)
    }

    @Test func settingChoicesAreTheFourStops() {
        #expect(LogLevel.settingChoices == [.off, .error, .notice, .debug])
    }

    @Test func errorInfoCapturesDomainCodeAndUnderlying() {
        let underlying = NSError(domain: "POSIXErrorDomain", code: 2,
                                 userInfo: [NSLocalizedDescriptionKey: "No such file"])
        let error = NSError(domain: "NSCocoaErrorDomain", code: 260,
                            userInfo: [
                                NSLocalizedDescriptionKey: "The file couldn't be opened.",
                                NSUnderlyingErrorKey: underlying,
                            ])
        let info = Log.ErrorInfo(error)

        #expect(info.domain == "NSCocoaErrorDomain")
        #expect(info.code == 260)
        #expect(info.description == "The file couldn't be opened.")
        #expect(info.underlying?.contains("No such file") == true)
        #expect(info.underlying?.contains("POSIXErrorDomain") == true)
        // The inline form (console + os.Logger tail) carries the queryable bits.
        #expect(info.inline.contains("NSCocoaErrorDomain 260"))
    }

    @Test func errorInfoWithoutUnderlyingIsNil() {
        let info = Log.ErrorInfo(URLError(.notConnectedToInternet))
        #expect(info.domain == NSURLErrorDomain)
        #expect(info.code == URLError.notConnectedToInternet.rawValue)
        #expect(info.underlying == nil)
    }

    @Test func entryRoundTripsThroughJSON() throws {
        // The console reads back what LogFile wrote, so encode/decode must match.
        let entry = Log.Entry(
            id: UUID(), time: Date(timeIntervalSince1970: 1_700_000_000), session: "abcd1234",
            level: .error, category: .updater, message: "boom",
            source: Log.Source(file: "Updater.swift", function: "check()", line: 42),
            error: Log.ErrorInfo(URLError(.timedOut))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Log.Entry.self, from: encoder.encode(entry))
        #expect(decoded == entry)
    }

    @Test func dayLabelNamesTodayAndYesterday() {
        let now = Date()
        #expect(LogsView.dayLabel(for: now) == "Today")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(LogsView.dayLabel(for: yesterday) == "Yesterday")
        // An older date falls through to the full weekday/date heading.
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let label = LogsView.dayLabel(for: old)
        #expect(label != "Today" && label != "Yesterday")
        #expect(label.contains("2020"))
    }
}
