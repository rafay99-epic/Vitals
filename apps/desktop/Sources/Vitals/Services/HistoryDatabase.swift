import Foundation
import SQLite3

/// The on-disk store for logged readings and fired alerts — a single SQLite
/// database in the channel-aware data home (`DataHome.historyDatabaseFile`),
/// replacing the old append-only CSV. SQLite gives reliable, indexed,
/// filterable storage: range queries stay fast no matter how much history
/// accumulates, where the CSV had to be read and parsed in full.
///
/// One connection guarded by a serial queue (SQLite is opened FULLMUTEX too, so
/// this is belt-and-braces): writes (`append`, `recordAlert`) are fire-and-forget
/// `async` so the main-thread tick never blocks on disk; reads (`samples`,
/// `recentAlerts`, exports) run `sync` and are always called off the main thread.
///
/// `HistoryReader` / `HistoryExport` / `AlertLog` remain the public API the views
/// use — they delegate here, so this is the one storage seam.
final class HistoryDatabase: @unchecked Sendable {
    static let shared = HistoryDatabase(
        file: DataHome.historyDatabaseFile,
        legacyReadings: [DataHome.historyPrevious, DataHome.historyFile],
        legacyAlerts: DataHome.alertsFile
    )

    /// One row of readings to log. Same shape the CSV logger used.
    struct Entry {
        let averageTemp: Double
        let hottestTemp: Double
        let gpuTemp: Double?
        let fanRPM: Double?
        let cpuUsage: Double
        let memoryUsedGB: Double
        let thermalState: String
        let batteryPercent: Double?
        let gpuUsage: Double?
        let gpuMemoryGB: Double?
    }

    private let queue = DispatchQueue(label: "com.vitals.history-db")
    private var db: OpaquePointer?
    private let dbFile: URL
    /// Legacy CSV files to import once (oldest first), then the alert log.
    private let legacyReadings: [URL]
    private let legacyAlerts: URL?
    /// Mirrors the CSV logger's cap: at most one readings row every 10 s, so the
    /// faster sampling tick can call `append` freely without bloating the table.
    private static let minimumWriteInterval: TimeInterval = 10
    private var lastWrite: Date = .distantPast
    /// Drop readings older than this so a machine left running for years can't
    /// grow the table without bound. Generous — a year at one row / 10 s is only
    /// ~3M rows. Alerts are tiny and never pruned.
    private static let retention: TimeInterval = 365 * 86_400

    /// `file` is the database path; `legacyReadings`/`legacyAlerts` are the old
    /// CSV / alert-log files imported once on first open (empty for tests).
    init(file: URL, legacyReadings: [URL] = [], legacyAlerts: URL? = nil) {
        self.dbFile = file
        self.legacyReadings = legacyReadings
        self.legacyAlerts = legacyAlerts
        queue.sync { open() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: Setup

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dbFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbFile.path, &db, flags, nil) == SQLITE_OK else {
            Log.error(.history, "couldn't open history database: \(lastErrorMessage)")
            if let db { sqlite3_close(db) }
            db = nil
            return
        }

        // WAL keeps a reader (the History view) and the writer (the tick) from
        // blocking each other; NORMAL sync is the right durability/speed trade for
        // best-effort telemetry; busy_timeout avoids spurious "database is locked".
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA busy_timeout=3000;")
        createSchema()
        importLegacyFilesIfNeeded()
        prune()
    }

    private func createSchema() {
        // `ts` is epoch milliseconds. `id` is the implicit rowid (monotonic), used
        // for even down-sampling. `ts UNIQUE` dedups (INSERT OR IGNORE) and indexes
        // it for range scans.
        exec("""
        CREATE TABLE IF NOT EXISTS samples (
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
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS alerts (
            id      INTEGER PRIMARY KEY,
            ts      INTEGER NOT NULL,
            message TEXT NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_alerts_ts ON alerts(ts);")
        exec("PRAGMA user_version=1;")
    }

    // MARK: Writes

    /// Append one readings row, throttled to one per 10 s. Fire-and-forget — the
    /// caller (the main-thread tick) never waits on disk.
    func append(_ entry: Entry) {
        let now = Date()
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            guard now.timeIntervalSince(self.lastWrite) >= Self.minimumWriteInterval else { return }
            self.lastWrite = now

            let sql = """
            INSERT OR IGNORE INTO samples
              (ts, avg_cpu, hottest_cpu, gpu_temp, fan_rpm, cpu_usage, memory_gb, thermal_state, battery_pct, gpu_usage, gpu_mem_gb)
            VALUES (?,?,?,?,?,?,?,?,?,?,?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Self.millis(now))
            sqlite3_bind_double(stmt, 2, entry.averageTemp)
            sqlite3_bind_double(stmt, 3, entry.hottestTemp)
            self.bindOptional(stmt, 4, entry.gpuTemp)
            self.bindOptional(stmt, 5, entry.fanRPM)
            sqlite3_bind_double(stmt, 6, entry.cpuUsage)
            sqlite3_bind_double(stmt, 7, entry.memoryUsedGB)
            sqlite3_bind_text(stmt, 8, entry.thermalState, -1, Self.transient)
            self.bindOptional(stmt, 9, entry.batteryPercent)
            self.bindOptional(stmt, 10, entry.gpuUsage)
            self.bindOptional(stmt, 11, entry.gpuMemoryGB)
            sqlite3_step(stmt)
        }
    }

    /// Record a fired alert (best-effort, fire-and-forget).
    func recordAlert(message: String, at time: Date) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO alerts (ts, message) VALUES (?,?);", -1, &stmt, nil) == SQLITE_OK
            else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Self.millis(time))
            sqlite3_bind_text(stmt, 2, message, -1, Self.transient)
            sqlite3_step(stmt)
        }
    }

    // MARK: Reads

    /// Readings within `range`, oldest→newest. For ranges with more rows than
    /// `maxPoints` it thins in SQL (every Nth row by rowid) so a huge "all" query
    /// still returns a chart-sized set without loading the whole table into memory.
    /// The caller (`HistoryReader.load`) does the final exact down-sample.
    func samples(range: HistoryRange, now: Date, maxPoints: Int) -> [HistorySample] {
        queue.sync {
            guard let db else { return [] }
            let cutoff: Int64 = range.seconds.map { Self.millis(now.addingTimeInterval(-$0)) } ?? 0

            let count = scalarCount("SELECT COUNT(*) FROM samples WHERE ts >= ?;", cutoff)
            guard count > 0 else { return [] }
            let stride = maxPoints > 0 ? max(1, count / Int64(maxPoints)) : 1

            var sql = "SELECT ts, avg_cpu, hottest_cpu, gpu_temp, fan_rpm, cpu_usage, memory_gb, thermal_state, battery_pct, gpu_usage, gpu_mem_gb FROM samples WHERE ts >= ?"
            if stride > 1 { sql += " AND id % \(stride) = 0" }
            sql += " ORDER BY ts ASC;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, cutoff)

            var out: [HistorySample] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(HistorySample(
                    time: Self.date(sqlite3_column_int64(stmt, 0)),
                    avgTemp: sqlite3_column_double(stmt, 1),
                    hottestTemp: sqlite3_column_double(stmt, 2),
                    gpuTemp: optionalDouble(stmt, 3),
                    fanRPM: optionalDouble(stmt, 4),
                    cpuUsage: sqlite3_column_double(stmt, 5),
                    memoryGB: sqlite3_column_double(stmt, 6),
                    thermalState: text(stmt, 7),
                    batteryPercent: optionalDouble(stmt, 8),
                    gpuUsage: optionalDouble(stmt, 9),
                    gpuMemoryGB: optionalDouble(stmt, 10)
                ))
            }
            return out
        }
    }

    /// The most recent fired alerts, newest first.
    func recentAlerts(limit: Int) -> [AlertEvent] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT ts, message FROM alerts ORDER BY ts DESC LIMIT ?;", -1, &stmt, nil) == SQLITE_OK
            else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(limit))
            var out: [AlertEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(AlertEvent(time: Self.date(sqlite3_column_int64(stmt, 0)), message: text(stmt, 1)))
            }
            return out
        }
    }

    // MARK: Maintenance

    /// Drop readings older than the retention window. Cheap (indexed delete);
    /// runs once at open.
    private func prune() {
        guard let db else { return }
        let cutoff = Self.millis(Date().addingTimeInterval(-Self.retention))
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM samples WHERE ts < ?;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, cutoff)
        sqlite3_step(stmt)
    }

    // MARK: Legacy import (CSV → SQLite, one time)

    /// On the first launch after upgrading, fold the old CSV log and alert log
    /// into the database, then rename the originals to `*.imported` so they're
    /// preserved (never deleted — they're the user's data) and never re-imported.
    /// `INSERT OR IGNORE` makes a partial/repeated run harmless.
    private func importLegacyFilesIfNeeded() {
        let fm = FileManager.default

        // Readings: previous file first (older rows), then the current one.
        if legacyReadings.contains(where: { fm.fileExists(atPath: $0.path) }) {
            var imported = 0
            exec("BEGIN;")
            for url in legacyReadings {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") {
                    guard let s = HistoryReader.parse(line) else { continue }
                    if insertSampleUnsafe(s) { imported += 1 }
                }
            }
            exec("COMMIT;")
            for url in legacyReadings where fm.fileExists(atPath: url.path) {
                try? fm.moveItem(at: url, to: url.appendingPathExtension("imported"))
            }
            if imported > 0 { Log.notice(.history, "imported \(imported) readings from CSV into SQLite") }
        }

        // Alerts.
        if let alertsURL = legacyAlerts, fm.fileExists(atPath: alertsURL.path),
           let text = try? String(contentsOf: alertsURL, encoding: .utf8) {
            exec("BEGIN;")
            var imported = 0
            for line in text.split(separator: "\n") {
                guard let event = AlertLog.parse(line) else { continue }
                recordAlertUnsafe(message: event.message, at: event.time); imported += 1
            }
            exec("COMMIT;")
            try? fm.moveItem(at: alertsURL, to: alertsURL.appendingPathExtension("imported"))
            if imported > 0 { Log.notice(.history, "imported \(imported) alerts from log into SQLite") }
        }
    }

    /// Insert one already-parsed sample synchronously (no throttle). For the
    /// importer and tests. Runs on the serial queue.
    func insert(_ sample: HistorySample) {
        queue.sync { _ = insertSampleUnsafe(sample) }
    }

    /// Insert one sample directly (must already be on `queue` — used by the
    /// importer, which runs inside `open`). Returns whether a row was added.
    private func insertSampleUnsafe(_ s: HistorySample) -> Bool {
        guard let db else { return false }
        let sql = """
        INSERT OR IGNORE INTO samples
          (ts, avg_cpu, hottest_cpu, gpu_temp, fan_rpm, cpu_usage, memory_gb, thermal_state, battery_pct, gpu_usage, gpu_mem_gb)
        VALUES (?,?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Self.millis(s.time))
        sqlite3_bind_double(stmt, 2, s.avgTemp)
        sqlite3_bind_double(stmt, 3, s.hottestTemp)
        bindOptional(stmt, 4, s.gpuTemp)
        bindOptional(stmt, 5, s.fanRPM)
        sqlite3_bind_double(stmt, 6, s.cpuUsage)
        sqlite3_bind_double(stmt, 7, s.memoryGB)
        sqlite3_bind_text(stmt, 8, s.thermalState, -1, Self.transient)
        bindOptional(stmt, 9, s.batteryPercent)
        bindOptional(stmt, 10, s.gpuUsage)
        bindOptional(stmt, 11, s.gpuMemoryGB)
        return sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
    }

    private func recordAlertUnsafe(message: String, at time: Date) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO alerts (ts, message) VALUES (?,?);", -1, &stmt, nil) == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Self.millis(time))
        sqlite3_bind_text(stmt, 2, message, -1, Self.transient)
        sqlite3_step(stmt)
    }

    // MARK: SQLite helpers

    /// SQLite wants to know whether a bound string outlives the bind; TRANSIENT
    /// tells it to copy, which is always correct here.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private static func date(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }

    private func exec(_ sql: String) {
        guard let db else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            Log.notice(.history, "history db exec failed: \(lastErrorMessage)")
        }
    }

    private func scalarCount(_ sql: String, _ bind: Int64) -> Int64 {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, bind)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    private func bindOptional(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value { sqlite3_bind_double(stmt, index, value) } else { sqlite3_bind_null(stmt, index) }
    }

    private func optionalDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, index)
    }

    private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
    }

    private var lastErrorMessage: String {
        db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
    }
}
