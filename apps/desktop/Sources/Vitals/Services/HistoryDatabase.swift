import Foundation
import SQLite3

/// Logged readings and fired alerts in one SQLite database in the data home.
///
/// One connection on a serial queue: writes (`append`, `recordAlert`) are
/// fire-and-forget so the main-thread tick never blocks on disk; reads run `sync`
/// and must be called off the main thread.
final class HistoryDatabase: @unchecked Sendable {
    static let shared = HistoryDatabase(file: DataHome.historyDatabaseFile)

    /// One row of readings to log.
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
        let netInBps: Double?
        let netOutBps: Double?
        let diskReadBps: Double?
        let diskWriteBps: Double?
        let socWatts: Double?
        let batteryWatts: Double?
    }

    private let queue = DispatchQueue(label: "com.vitals.history-db")
    private var db: OpaquePointer?
    private let dbFile: URL
    /// Drop readings older than this, checked daily. A year at one row / 10 s is
    /// ~3M rows. Alerts are tiny and never pruned.
    private static let retention: TimeInterval = 365 * 86_400
    private var lastPrune: Date = .distantPast

    init(file: URL) {
        self.dbFile = file
        // Async: `shared` is first touched by the main-thread tick. Every later
        // operation queues behind this, so it always runs after `open`.
        queue.async { self.open() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// Blocks until `open` has finished, for tests.
    func waitUntilReady() { queue.sync {} }

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
        pruneIfDue(Date())
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
            gpu_mem_gb    REAL,
            net_in_bps    REAL,
            net_out_bps   REAL,
            disk_read_bps  REAL,
            disk_write_bps REAL,
            soc_watts      REAL,
            battery_watts  REAL
        );
        """)
        // Older files lack newer columns and CREATE TABLE IF NOT EXISTS won't add
        // them. Column *presence* is the gate, not `user_version`, so a crash
        // mid-migration can't wedge the file and re-running is a no-op.
        addSampleColumnIfMissing("net_in_bps")
        addSampleColumnIfMissing("net_out_bps")
        addSampleColumnIfMissing("disk_read_bps")
        addSampleColumnIfMissing("disk_write_bps")
        addSampleColumnIfMissing("soc_watts")
        addSampleColumnIfMissing("battery_watts")
        // A fired alert is identified by when + what. Distinct alerts differ in ts
        // (the cooldown spaces repeats), so INSERT OR IGNORE loses none.
        exec("""
        CREATE TABLE IF NOT EXISTS alerts (
            id      INTEGER PRIMARY KEY,
            ts      INTEGER NOT NULL,
            message TEXT NOT NULL,
            UNIQUE(ts, message)
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_alerts_ts ON alerts(ts);")
        // v5: per-app energy logging was removed. Drop its table once and
        // VACUUM so the file actually shrinks (a DROP alone keeps the pages).
        if userVersion < 5 {
            exec("DROP TABLE IF EXISTS app_energy;")
            exec("VACUUM;")
        }
        exec("PRAGMA user_version=5;")
    }

    /// Adds a `REAL` column to `samples` if missing. SQLite's ALTER TABLE has no
    /// IF NOT EXISTS, so existence comes from `table_info`. `column` is always a
    /// constant name, never input.
    private func addSampleColumnIfMissing(_ column: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(samples);", -1, &stmt, nil) == SQLITE_OK else { return }
        var exists = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if text(stmt, 1) == column { exists = true; break }
        }
        sqlite3_finalize(stmt)
        guard !exists else { return }
        exec("ALTER TABLE samples ADD COLUMN \(column) REAL;")
        Log.notice(.history, "history db: added \(column) column")
    }

    // MARK: Writes

    /// Append one readings row. Fire-and-forget; the caller (the tick) throttles.
    func append(_ entry: Entry, at now: Date = Date()) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            self.pruneIfDue(now)

            let sql = """
            INSERT OR IGNORE INTO samples
              (ts, avg_cpu, hottest_cpu, gpu_temp, fan_rpm, cpu_usage, memory_gb, thermal_state, battery_pct, gpu_usage, gpu_mem_gb, net_in_bps, net_out_bps, disk_read_bps, disk_write_bps, soc_watts, battery_watts)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
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
            self.bindOptional(stmt, 12, entry.netInBps)
            self.bindOptional(stmt, 13, entry.netOutBps)
            self.bindOptional(stmt, 14, entry.diskReadBps)
            self.bindOptional(stmt, 15, entry.diskWriteBps)
            self.bindOptional(stmt, 16, entry.socWatts)
            self.bindOptional(stmt, 17, entry.batteryWatts)
            sqlite3_step(stmt)
        }
    }

    /// Record a fired alert (best-effort, fire-and-forget).
    func recordAlert(message: String, at time: Date) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO alerts (ts, message) VALUES (?,?);", -1, &stmt, nil) == SQLITE_OK
            else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Self.millis(time))
            sqlite3_bind_text(stmt, 2, message, -1, Self.transient)
            sqlite3_step(stmt)
        }
    }

    // MARK: Reads

    /// Readings within `range`, oldest→newest. Over `maxPoints` rows it thins in
    /// SQL (every Nth rowid) so "all" never loads the whole table.
    /// `HistoryReader.load` does the final exact down-sample.
    func samples(range: HistoryRange, now: Date, maxPoints: Int) -> [HistorySample] {
        queue.sync {
            guard let db else { return [] }
            let cutoff: Int64 = range.seconds.map { Self.millis(now.addingTimeInterval(-$0)) } ?? 0

            let count = scalarCount("SELECT COUNT(*) FROM samples WHERE ts >= ?;", cutoff)
            guard count > 0 else { return [] }
            let stride = maxPoints > 0 ? max(1, count / Int64(maxPoints)) : 1

            // `cutoff` and `stride` are computed Int64s, never input, so inlining
            // is safe. The thinned query also pins the true first/last rows so the
            // chart's endpoints are real readings.
            var sql = "SELECT ts, avg_cpu, hottest_cpu, gpu_temp, fan_rpm, cpu_usage, memory_gb, thermal_state, battery_pct, gpu_usage, gpu_mem_gb, net_in_bps, net_out_bps, disk_read_bps, disk_write_bps, soc_watts, battery_watts FROM samples WHERE ts >= \(cutoff)"
            if stride > 1 {
                sql += " AND (id % \(stride) = 0"
                    + " OR id = (SELECT MIN(id) FROM samples WHERE ts >= \(cutoff))"
                    + " OR id = (SELECT MAX(id) FROM samples WHERE ts >= \(cutoff)))"
            }
            sql += " ORDER BY ts ASC;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

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
                    gpuMemoryGB: optionalDouble(stmt, 10),
                    netInBps: optionalDouble(stmt, 11),
                    netOutBps: optionalDouble(stmt, 12),
                    diskReadBps: optionalDouble(stmt, 13),
                    diskWriteBps: optionalDouble(stmt, 14),
                    socWatts: optionalDouble(stmt, 15),
                    batteryWatts: optionalDouble(stmt, 16)
                ))
            }
            return out
        }
    }

    /// The most recent fired alerts, newest first. `id DESC` breaks ts ties so the
    /// order is deterministic (insertion order) rather than arbitrary.
    func recentAlerts(limit: Int) -> [AlertEvent] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT ts, message FROM alerts ORDER BY ts DESC, id DESC LIMIT ?;", -1, &stmt, nil) == SQLITE_OK
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

    /// Streams every readings row, oldest→newest, to `body` without materializing
    /// the table (CSV export of ~3M rows). Call off the main thread.
    func forEachSample(_ body: (HistorySample) -> Void) {
        queue.sync {
            guard let db else { return }
            let sql = "SELECT ts, avg_cpu, hottest_cpu, gpu_temp, fan_rpm, cpu_usage, memory_gb, thermal_state, battery_pct, gpu_usage, gpu_mem_gb, net_in_bps, net_out_bps, disk_read_bps, disk_write_bps, soc_watts, battery_watts FROM samples ORDER BY ts ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                body(HistorySample(
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
                    gpuMemoryGB: optionalDouble(stmt, 10),
                    netInBps: optionalDouble(stmt, 11),
                    netOutBps: optionalDouble(stmt, 12),
                    diskReadBps: optionalDouble(stmt, 13),
                    diskWriteBps: optionalDouble(stmt, 14),
                    socWatts: optionalDouble(stmt, 15),
                    batteryWatts: optionalDouble(stmt, 16)
                ))
            }
        }
    }

    // MARK: Maintenance

    /// Drop readings past retention, at most once a day (an indexed delete).
    /// Must run on `queue`.
    private func pruneIfDue(_ now: Date) {
        guard let db, now.timeIntervalSince(lastPrune) >= 86_400 else { return }
        lastPrune = now
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM samples WHERE ts < ?;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Self.millis(now.addingTimeInterval(-Self.retention)))
        sqlite3_step(stmt)
    }

    /// Insert one sample synchronously. For tests.
    func insert(_ sample: HistorySample) {
        queue.sync { _ = insertSampleUnsafe(sample) }
    }

    /// Insert one sample; must already be on `queue`. Returns whether a row was added.
    private func insertSampleUnsafe(_ s: HistorySample) -> Bool {
        guard let db else { return false }
        let sql = """
        INSERT OR IGNORE INTO samples
          (ts, avg_cpu, hottest_cpu, gpu_temp, fan_rpm, cpu_usage, memory_gb, thermal_state, battery_pct, gpu_usage, gpu_mem_gb, net_in_bps, net_out_bps, disk_read_bps, disk_write_bps, soc_watts, battery_watts)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
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
        bindOptional(stmt, 12, s.netInBps)
        bindOptional(stmt, 13, s.netOutBps)
        bindOptional(stmt, 14, s.diskReadBps)
        bindOptional(stmt, 15, s.diskWriteBps)
        bindOptional(stmt, 16, s.socWatts)
        bindOptional(stmt, 17, s.batteryWatts)
        return sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
    }

    // MARK: SQLite helpers

    private var userVersion: Int64 {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

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
