import Testing
import Foundation
import SQLite3
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

    // MARK: v1 schema fixture + raw introspection (for the migration tests)

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Builds a REAL pre-v2 database on disk by hand: the OLD 11-column `samples`
    /// schema, `user_version = 1`, and the given rows — so the migration is
    /// exercised against the exact shape shipped before this change, not a mock.
    private func makeV1Database(at url: URL, rows: [(ts: Int64, avgCpu: Double, hottestCpu: Double, thermal: String, battery: Double?)]) {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let create = """
        CREATE TABLE samples (
            id            INTEGER PRIMARY KEY,
            ts            INTEGER NOT NULL UNIQUE,
            avg_cpu       REAL NOT NULL,
            hottest_cpu   REAL NOT NULL,
            gpu_temp      REAL,
            fan_rpm       REAL,
            cpu_usage     REAL NOT NULL,
            memory_gb     REAL NOT NULL,
            thermal_state TEXT NOT NULL,
            battery_pct   REAL,
            gpu_usage     REAL,
            gpu_mem_gb    REAL
        );
        """
        #expect(sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA user_version=1;", nil, nil, nil) == SQLITE_OK)
        for r in rows {
            var stmt: OpaquePointer?
            let sql = "INSERT INTO samples (ts, avg_cpu, hottest_cpu, cpu_usage, memory_gb, thermal_state, battery_pct) VALUES (?,?,?,?,?,?,?);"
            #expect(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
            sqlite3_bind_int64(stmt, 1, r.ts)
            sqlite3_bind_double(stmt, 2, r.avgCpu)
            sqlite3_bind_double(stmt, 3, r.hottestCpu)
            sqlite3_bind_double(stmt, 4, 12.3)
            sqlite3_bind_double(stmt, 5, 10.4)
            sqlite3_bind_text(stmt, 6, r.thermal, -1, Self.sqliteTransient)
            if let b = r.battery { sqlite3_bind_double(stmt, 7, b) } else { sqlite3_bind_null(stmt, 7) }
            #expect(sqlite3_step(stmt) == SQLITE_DONE)
            sqlite3_finalize(stmt)
        }
    }

    /// The stored `PRAGMA user_version` read via a fresh connection (-1 on failure).
    private func userVersion(at url: URL) -> Int64 {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : -1
    }

    /// The column names on `samples` read via a fresh connection.
    private func sampleColumns(at url: URL) -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(samples);", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var names: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) { names.insert(String(cString: c)) }
        }
        return names
    }

    private static let v2Columns: Set<String> = ["net_down_bps", "net_up_bps", "cycle_count", "max_capacity_pct"]

    private func sample(_ secondsAgo: TimeInterval, now: Date, gpuTemp: Double? = nil,
                        fanRPM: Double? = nil, battery: Double? = nil) -> HistorySample {
        HistorySample(
            time: now.addingTimeInterval(-secondsAgo),
            avgTemp: 45.5, hottestTemp: 52.0, gpuTemp: gpuTemp, fanRPM: fanRPM,
            cpuUsage: 12.3, memoryGB: 10.4, thermalState: "Nominal",
            batteryPercent: battery, gpuUsage: nil, gpuMemoryGB: nil)
    }

    @Test func roundTripsRowsAndOptionals() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        db.insert(sample(20, now: now, gpuTemp: nil, fanRPM: 1200, battery: 87))

        let rows = db.samples(range: .all, now: now, maxPoints: 600)
        #expect(rows.count == 1)
        let r = try #require(rows.first)
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

    // MARK: Daily battery health (SQL-side day bucketing)

    @Test func dailyBatteryHealthPicksLatestPerDayAndExcludesNilCapacity() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)

        // Align to a UTC day boundary so adding a couple of hours can't spill
        // into the next day's bucket.
        let epochDay = Int64(1_700_000_000) / 86_400
        let day1Start = Date(timeIntervalSince1970: Double(epochDay * 86_400))
        let day2Start = day1Start.addingTimeInterval(3 * 86_400)   // a different day

        func s(_ time: Date, cycles: Int?, pct: Double?) -> HistorySample {
            HistorySample(time: time, avgTemp: 45, hottestTemp: 50, gpuTemp: nil, fanRPM: nil,
                          cpuUsage: 10, memoryGB: 8, thermalState: "Nominal",
                          batteryPercent: 80, gpuUsage: nil, gpuMemoryGB: nil,
                          cycleCount: cycles, maxCapacityPct: pct)
        }

        db.insert(s(day1Start, cycles: 100, pct: 92.0))                          // day 1, earliest
        db.insert(s(day1Start.addingTimeInterval(3600), cycles: 101, pct: 91.8)) // day 1, LATEST
        db.insert(s(day1Start.addingTimeInterval(7200), cycles: nil, pct: nil))  // day 1, no health reading
        db.insert(s(day2Start, cycles: 150, pct: 90.0))                          // day 2, only reading

        let points = db.dailyBatteryHealth()
        #expect(points.count == 2)   // two calendar days, not four samples
        #expect(points[0].cycleCount == 101)
        #expect(points[0].capacityPct == 91.8)   // the day's LATEST reading, not the first
        #expect(points[1].cycleCount == 150)
        #expect(points[1].capacityPct == 90.0)
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

    @Test func dedupsIdenticalAlerts() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        db.recordAlert(message: "same", at: t)
        db.recordAlert(message: "same", at: t)        // identical (ts, message) → ignored
        db.recordAlert(message: "different", at: t)   // same ts, new message → kept
        #expect(db.recentAlerts(limit: 10).count == 2)
    }

    @Test func importsLegacyCSVAndRenamesIt() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("vitals-mig-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // A legacy CSV in the exact logged format: header + two valid rows + one
        // malformed line that must be skipped. Timestamps are recent (relative to
        // now) so the retention prune never deletes them, whatever year the test runs.
        let now = Date()
        let iso = HistoryReader.isoFormatter
        let csv = dir.appendingPathComponent("history.csv")
        try (HistoryExport.csvHeader +
             "\(iso.string(from: now.addingTimeInterval(-20))),43.5,52.6,,1200,12.3,10.40,Nominal,87,49.0,0.79\n" +
             "\(iso.string(from: now.addingTimeInterval(-10))),44.0,53.0,,1300,15.0,10.50,Fair,86,50.0,0.80\n" +
             "garbage,line\n").write(to: csv, atomically: true, encoding: .utf8)

        let alerts = dir.appendingPathComponent("alerts.log")
        try "\(iso.string(from: now.addingTimeInterval(-15)))\tCPU temperature is 92°C.\n"
            .write(to: alerts, atomically: true, encoding: .utf8)

        let db = HistoryDatabase(file: dir.appendingPathComponent("history.sqlite3"),
                                 legacyReadings: [csv], legacyAlerts: alerts)

        let rows = db.samples(range: .all, now: now, maxPoints: 600)
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

    // MARK: Schema migration (v1 → v2)

    @Test func migratesV1DatabaseToV2PreservingData() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        // Real now (not a fixed 2023 epoch) so the retention prune in open() keeps
        // the fixture rows whatever year the test runs.
        let now = Date()
        func ms(_ secondsAgo: TimeInterval) -> Int64 {
            Int64((now.addingTimeInterval(-secondsAgo).timeIntervalSince1970 * 1000).rounded())
        }
        makeV1Database(at: url, rows: [
            (ms(40), 40.0, 50.0, "Nominal", 90),
            (ms(20), 42.0, 52.0, "Fair", nil),
        ])
        #expect(userVersion(at: url) == 1)                       // fixture really is v1
        #expect(sampleColumns(at: url).isDisjoint(with: Self.v2Columns))

        // Open through the real init/open path → runs migrateSchemaIfNeeded().
        let db = HistoryDatabase(file: url)
        db.waitUntilReady()

        // New columns exist, version stamped 2.
        #expect(sampleColumns(at: url).isSuperset(of: Self.v2Columns))
        #expect(userVersion(at: url) == 2)

        // Old rows intact and readable, with nil for the new fields.
        let rows = db.samples(range: .all, now: now, maxPoints: 600)
        #expect(rows.count == 2)
        let first = try #require(rows.first)
        #expect(first.avgTemp == 40.0)
        #expect(first.batteryPercent == 90)
        #expect(first.netDownBps == nil)
        #expect(first.netUpBps == nil)
        #expect(first.cycleCount == nil)
        #expect(first.maxCapacityPct == nil)
        #expect(rows.last?.batteryPercent == nil)   // NULL battery preserved as nil

        // A fresh append with all four new fields set round-trips through the
        // migrated table.
        db.insert(HistorySample(
            time: now, avgTemp: 46, hottestTemp: 55, gpuTemp: nil, fanRPM: nil,
            cpuUsage: 20, memoryGB: 11, thermalState: "Nominal", batteryPercent: 80,
            gpuUsage: nil, gpuMemoryGB: nil,
            netDownBps: 1_500_000, netUpBps: 250_000, cycleCount: 143, maxCapacityPct: 91.5))
        let newest = try #require(db.samples(range: .all, now: now, maxPoints: 600).last)
        #expect(newest.netDownBps == 1_500_000)
        #expect(newest.netUpBps == 250_000)
        #expect(newest.cycleCount == 143)
        #expect(newest.maxCapacityPct == 91.5)
    }

    @Test func migrationIsIdempotent() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let ts = Int64((now.addingTimeInterval(-10).timeIntervalSince1970 * 1000).rounded())
        makeV1Database(at: url, rows: [(ts, 40.0, 50.0, "Nominal", 90)])

        let first = HistoryDatabase(file: url); first.waitUntilReady()
        #expect(userVersion(at: url) == 2)

        // Open the (already-migrated) store a second time: the open path must be a
        // no-op — no error, still v2, columns and the row unchanged.
        let second = HistoryDatabase(file: url); second.waitUntilReady()
        #expect(userVersion(at: url) == 2)
        #expect(sampleColumns(at: url).isSuperset(of: Self.v2Columns))
        #expect(second.samples(range: .all, now: now, maxPoints: 600).count == 1)
        _ = first   // keep the first connection alive until the assertions run
    }

    @Test func freshInstallHasV2Schema() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url); db.waitUntilReady()
        #expect(userVersion(at: url) == 2)
        #expect(sampleColumns(at: url).isSuperset(of: Self.v2Columns))
        _ = db
    }

    // MARK: CSV round-trip for the new trailing columns

    @Test func csvExportAndParseRoundTripNewFields() throws {
        let original = HistorySample(
            time: Date(timeIntervalSince1970: 1_700_000_000),
            avgTemp: 45.5, hottestTemp: 52.0, gpuTemp: nil, fanRPM: 1200,
            cpuUsage: 12.3, memoryGB: 10.4, thermalState: "Nominal",
            batteryPercent: 87, gpuUsage: nil, gpuMemoryGB: nil,
            netDownBps: 1_500_000, netUpBps: 250_000, cycleCount: 143, maxCapacityPct: 91.5)
        let line = HistoryExport.csvLine(original)              // trailing "\n"
        let parsed = try #require(HistoryReader.parse(line.dropLast()))
        #expect(parsed.netDownBps == 1_500_000)
        #expect(parsed.netUpBps == 250_000)
        #expect(parsed.cycleCount == 143)
        #expect(parsed.maxCapacityPct == 91.5)
        #expect(parsed.fanRPM == 1200)                          // legacy fields survive too
        #expect(parsed.batteryPercent == 87)
    }

    @Test func legacyElevenColumnLineParsesWithNilNewFields() {
        let iso = HistoryReader.isoFormatter.string(from: Date(timeIntervalSince1970: 1_700_000_000))
        let legacy = Substring("\(iso),43.5,52.6,,1200,12.3,10.40,Nominal,87,49.0,0.79")
        let s = HistoryReader.parse(legacy)
        #expect(s?.gpuMemoryGB == 0.79)   // legacy columns still parse exactly as before
        #expect(s?.netDownBps == nil)
        #expect(s?.netUpBps == nil)
        #expect(s?.cycleCount == nil)
        #expect(s?.maxCapacityPct == nil)
    }
}
