import Testing
import Foundation
@testable import Vitals

/// Locks the SQLite history store: rows round-trip with their optionals intact,
/// range queries filter by time, duplicate timestamps are ignored, alerts persist,
/// and the one-time CSV/alert-log import folds legacy data in (and renames the
/// originals so it never re-imports).
struct HistoryDatabaseTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vitals-hdb-\(UUID().uuidString).sqlite3")
    }

    private func sample(_ secondsAgo: TimeInterval, now: Date, gpuTemp: Double? = nil,
                        fanRPM: Double? = nil, battery: Double? = nil) -> HistorySample {
        HistorySample(
            time: now.addingTimeInterval(-secondsAgo),
            avgTemp: 45.5, hottestTemp: 52.0, gpuTemp: gpuTemp, fanRPM: fanRPM,
            cpuUsage: 12.3, memoryGB: 10.4, thermalState: "Nominal",
            batteryPercent: battery, gpuUsage: nil, gpuMemoryGB: nil)
    }

    @Test func roundTripsRowsAndOptionals() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        db.insert(sample(20, now: now, gpuTemp: nil, fanRPM: 1200, battery: 87))

        let rows = db.samples(range: .all, now: now, maxPoints: 600)
        #expect(rows.count == 1)
        let r = rows[0]
        #expect(r.avgTemp == 45.5)
        #expect(r.gpuTemp == nil)          // NULL column → nil, not 0
        #expect(r.fanRPM == 1200)
        #expect(r.batteryPercent == 87)
        #expect(r.thermalState == "Nominal")
        // Stored as epoch millis — round-trips to ms precision.
        #expect(abs(r.time.timeIntervalSince1970 - now.addingTimeInterval(-20).timeIntervalSince1970) < 0.001)
    }

    @Test func rangeFiltersByTime() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        db.insert(sample(30, now: now))         // within the hour
        db.insert(sample(7200, now: now))       // two hours ago — outside the hour

        #expect(db.samples(range: .hour, now: now, maxPoints: 600).count == 1)
        #expect(db.samples(range: .all, now: now, maxPoints: 600).count == 2)
    }

    @Test func ignoresDuplicateTimestamps() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let s = sample(10, now: now)
        db.insert(s)
        db.insert(s)   // same ts → INSERT OR IGNORE drops it
        #expect(db.samples(range: .all, now: now, maxPoints: 600).count == 1)
    }

    @Test func recordsAndReadsAlerts() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        db.recordAlert(message: "CPU 92°C — above your 90°C alert.", at: t)
        // Serial queue: this sync read runs after the async write.
        let recent = db.recentAlerts(limit: 10)
        #expect(recent.count == 1)
        #expect(recent.first?.message == "CPU 92°C — above your 90°C alert.")
    }

    @Test func importsLegacyCSVAndRenamesIt() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("vitals-mig-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // A legacy CSV in the exact logged format: header + two valid rows + one
        // malformed line that must be skipped.
        let csv = dir.appendingPathComponent("history.csv")
        try (HistoryExport.csvHeader +
             "2026-06-16T01:02:03Z,43.5,52.6,,1200,12.3,10.40,Nominal,87,49.0,0.79\n" +
             "2026-06-16T01:02:13Z,44.0,53.0,,1300,15.0,10.50,Fair,86,50.0,0.80\n" +
             "garbage,line\n").write(to: csv, atomically: true, encoding: .utf8)

        let alerts = dir.appendingPathComponent("alerts.log")
        try "2026-06-16T01:02:03Z\tCPU temperature is 92°C.\n".write(to: alerts, atomically: true, encoding: .utf8)

        let db = HistoryDatabase(file: dir.appendingPathComponent("history.sqlite3"),
                                 legacyReadings: [csv], legacyAlerts: alerts)

        let rows = db.samples(range: .all, now: Date(timeIntervalSince1970: 1_771_000_000), maxPoints: 600)
        #expect(rows.count == 2)                              // malformed line skipped
        #expect(db.recentAlerts(limit: 10).count == 1)

        // Originals preserved (not deleted) and renamed so they won't re-import.
        #expect(!fm.fileExists(atPath: csv.path))
        #expect(fm.fileExists(atPath: csv.appendingPathExtension("imported").path))
        #expect(fm.fileExists(atPath: alerts.appendingPathExtension("imported").path))
    }

    @Test func removesStaleImportedBackupsAfterGracePeriod() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("vitals-clean-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // A backup from a migration 3 days ago — past the 2-day grace.
        let staleBase = dir.appendingPathComponent("history.csv")
        let stale = staleBase.appendingPathExtension("imported")
        try "old data".write(to: stale, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86_400)], ofItemAtPath: stale.path)

        // A backup from a migration just now — still within grace.
        let freshBase = dir.appendingPathComponent("alerts.log")
        let fresh = freshBase.appendingPathExtension("imported")
        try "new data".write(to: fresh, atomically: true, encoding: .utf8)

        // The base files don't exist, so nothing imports — only the cleanup runs.
        let db = HistoryDatabase(file: dir.appendingPathComponent("history.sqlite3"),
                                 legacyReadings: [staleBase], legacyAlerts: freshBase)
        db.waitUntilReady()   // open() runs async — let it finish before asserting

        #expect(!fm.fileExists(atPath: stale.path))   // stale backup auto-removed
        #expect(fm.fileExists(atPath: fresh.path))    // fresh backup kept (still in grace)
    }
}
