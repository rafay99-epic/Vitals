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
        let netInBps: Double?
        let netOutBps: Double?
        let diskReadBps: Double?
        let diskWriteBps: Double?
        let socWatts: Double?
        let batteryWatts: Double?
    }

    /// One per-app energy row, logged in batches at a coarse cadence. `bundleID`
    /// is nil for processes not inside an `.app`. `avgWatts` is a real reading
    /// (nil when the OS reported no energy); `preventsSleep` marks apps holding a
    /// system-sleep assertion.
    struct AppEnergyRow {
        let bundleID: String?
        let name: String
        let avgWatts: Double?
        let cpuPercent: Double
        let wakeupsPerSec: Double
        let preventsSleep: Bool
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
    /// App-energy rows are many-per-tick, so they're logged on their own coarse
    /// cadence (once a minute) to keep the table bounded.
    private static let appEnergyWriteInterval: TimeInterval = 60
    private var lastAppEnergyWrite: Date = .distantPast
    /// Drop readings older than this so a machine left running for years can't
    /// grow the table without bound. Generous — a year at one row / 10 s is only
    /// ~3M rows. Alerts are tiny and never pruned.
    private static let retention: TimeInterval = 365 * 86_400
    /// App-energy rows are many-per-sample (top apps × once a minute), so they're
    /// kept for a shorter window than the single-row `samples` series.
    private static let appEnergyRetention: TimeInterval = 14 * 86_400
    /// How long the imported legacy files (`*.imported`) are kept after migration
    /// as a safety net before being deleted automatically, so they don't linger
    /// in the data home and confuse the user. Measured from the migration moment.
    private static let importedGracePeriod: TimeInterval = 2 * 86_400

    /// `file` is the database path; `legacyReadings`/`legacyAlerts` are the old
    /// CSV / alert-log files imported once on first open (empty for tests).
    init(file: URL, legacyReadings: [URL] = [], legacyAlerts: URL? = nil) {
        self.dbFile = file
        self.legacyReadings = legacyReadings
        self.legacyAlerts = legacyAlerts
        // Open + the one-time CSV import (which can parse a large file) run
        // asynchronously on the queue — `shared` is first touched by the
        // main-thread tick, and this must never block it. Every later operation is
        // dispatched to the same serial queue, so it naturally runs after `open`.
        queue.async { self.open() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// Blocks until `open` (and any one-time import) has finished — for tests that
    /// assert on `open`'s side effects right after construction.
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
        // Don't clean up on the same launch we migrate: the freshly-retired
        // backups are brand new, and skipping avoids any chance of deleting one
        // whose timestamp stamp didn't take. Stale backups are swept on a later,
        // non-migrating launch.
        let migratedNow = importLegacyFilesIfNeeded()
        if !migratedNow { removeStaleImportedFiles() }
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
            gpu_mem_gb    REAL,
            net_in_bps    REAL,
            net_out_bps   REAL,
            disk_read_bps  REAL,
            disk_write_bps REAL,
            soc_watts      REAL,
            battery_watts  REAL
        );
        """)
        // Migrations (v1 → v2 network, v2 → v3 disk I/O): earlier versions
        // shipped `samples` without the newer columns, and CREATE TABLE IF NOT
        // EXISTS won't touch an existing table. Column *presence* is the gate —
        // not `user_version` — so a crash between the ALTER and the version
        // stamp can't wedge a half-migrated database, and re-running is always
        // a no-op.
        addSampleColumnIfMissing("net_in_bps")
        addSampleColumnIfMissing("net_out_bps")
        addSampleColumnIfMissing("disk_read_bps")
        addSampleColumnIfMissing("disk_write_bps")
        // v3 → v4: system-on-chip package watts + battery load watts.
        addSampleColumnIfMissing("soc_watts")
        addSampleColumnIfMissing("battery_watts")
        // UNIQUE(ts, message): a fired alert is identified by when + what, so
        // re-importing the alert log (e.g. a crash between import and retire) can't
        // duplicate rows — INSERT OR IGNORE makes it idempotent. Distinct alerts
        // differ in ts (the cooldown spaces repeats), so none are lost.
        exec("""
        CREATE TABLE IF NOT EXISTS alerts (
            id      INTEGER PRIMARY KEY,
            ts      INTEGER NOT NULL,
            message TEXT NOT NULL,
            UNIQUE(ts, message)
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_alerts_ts ON alerts(ts);")

        // Per-app energy history. One row per logged app per batch (a batch shares
        // one `ts`), so this is one-to-many where `samples` is one row per tick.
        // Indexed on ts for range scans and retention pruning.
        exec("""
        CREATE TABLE IF NOT EXISTS app_energy (
            id             INTEGER PRIMARY KEY,
            ts             INTEGER NOT NULL,
            bundle_id      TEXT,
            name           TEXT NOT NULL,
            avg_watts       REAL,
            cpu_pct         REAL,
            wakeups_per_sec REAL,
            prevents_sleep  INTEGER NOT NULL DEFAULT 0
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_app_energy_ts ON app_energy(ts);")
        exec("PRAGMA user_version=4;")
    }

    /// Adds a `REAL` column to `samples` if it isn't there yet. SQLite's ALTER
    /// TABLE has no IF NOT EXISTS, so existence comes from `table_info` — which
    /// makes the migration idempotent regardless of what version stamp the file
    /// carries. `column` is always one of our own constant names, never input.
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

    /// Append a batch of per-app energy rows sharing one timestamp. Throttled to
    /// one batch per minute; fire-and-forget on the serial queue. `rows` should
    /// already be capped to the interesting apps (top consumers + sleep blockers)
    /// by the caller.
    func appendAppEnergy(_ rows: [AppEnergyRow], at time: Date) {
        guard !rows.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            guard time.timeIntervalSince(self.lastAppEnergyWrite) >= Self.appEnergyWriteInterval else { return }
            self.lastAppEnergyWrite = time
            let ts = Self.millis(time)
            let sql = """
            INSERT INTO app_energy (ts, bundle_id, name, avg_watts, cpu_pct, wakeups_per_sec, prevents_sleep)
            VALUES (?,?,?,?,?,?,?);
            """
            self.exec("BEGIN;")
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                for row in rows {
                    sqlite3_bind_int64(stmt, 1, ts)
                    if let bundleID = row.bundleID { sqlite3_bind_text(stmt, 2, bundleID, -1, Self.transient) }
                    else { sqlite3_bind_null(stmt, 2) }
                    sqlite3_bind_text(stmt, 3, row.name, -1, Self.transient)
                    self.bindOptional(stmt, 4, row.avgWatts)
                    sqlite3_bind_double(stmt, 5, row.cpuPercent)
                    sqlite3_bind_double(stmt, 6, row.wakeupsPerSec)
                    sqlite3_bind_int(stmt, 7, row.preventsSleep ? 1 : 0)
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                }
                sqlite3_finalize(stmt)
            }
            self.exec("COMMIT;")
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

            // `cutoff` and `stride` are computed Int64s (never user input), so
            // inlining them is safe — and lets the thinned query also pin the true
            // first/last in-range rows, so the chart's endpoints are the real
            // newest/oldest readings, not just the nearest surviving sample.
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

    /// Stream every readings row, oldest→newest, to `body` — without materializing
    /// the whole table. Used by CSV export so a year of history (~3M rows) never
    /// loads into memory at once. Runs on the serial queue; call off the main thread.
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

    /// Stream every per-app energy row, oldest→newest, to `body` (with its batch
    /// timestamp) — without materializing the table. Used by CSV export. Runs on
    /// the serial queue; call off the main thread.
    func forEachAppEnergy(_ body: (Date, AppEnergyRow) -> Void) {
        queue.sync {
            guard let db else { return }
            let sql = "SELECT ts, bundle_id, name, avg_watts, cpu_pct, wakeups_per_sec, prevents_sleep FROM app_energy ORDER BY ts ASC, id ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let bundleID = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : text(stmt, 1)
                body(Self.date(sqlite3_column_int64(stmt, 0)), AppEnergyRow(
                    bundleID: bundleID,
                    name: text(stmt, 2),
                    avgWatts: optionalDouble(stmt, 3),
                    cpuPercent: sqlite3_column_double(stmt, 4),
                    wakeupsPerSec: sqlite3_column_double(stmt, 5),
                    preventsSleep: sqlite3_column_int(stmt, 6) != 0
                ))
            }
        }
    }

    // MARK: Maintenance

    /// Drop rows older than their retention window. Cheap (indexed deletes);
    /// runs once at open.
    private func prune() {
        pruneTable("samples", olderThan: Self.retention)
        pruneTable("app_energy", olderThan: Self.appEnergyRetention)
    }

    private func pruneTable(_ table: String, olderThan retention: TimeInterval) {
        guard let db else { return }
        let cutoff = Self.millis(Date().addingTimeInterval(-retention))
        // `table` is always one of our own constant names, never input.
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM \(table) WHERE ts < ?;", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, cutoff)
        sqlite3_step(stmt)
    }

    // MARK: Legacy import (CSV → SQLite, one time)

    /// On the first launch after upgrading, fold the old CSV log and alert log
    /// into the database, then retire the originals to `*.imported`. Returns
    /// whether anything was retired this run.
    ///
    /// Data-safety: a file is only retired if it was actually read **and** the
    /// import left rows in the database — so a file we couldn't open, or an import
    /// that failed (no DB, disk full), leaves the user's raw CSV exactly where it
    /// is for a later retry rather than renaming (and eventually deleting) the only
    /// copy. `INSERT OR IGNORE` on the `ts UNIQUE` key makes a repeated run safe.
    private func importLegacyFilesIfNeeded() -> Bool {
        guard db != nil else { return false }   // open failed — never touch the user's files
        let fm = FileManager.default
        var retiredAny = false

        // Readings: previous file first (older rows), then the current one.
        if legacyReadings.contains(where: { fm.fileExists(atPath: $0.path) }) {
            var imported = 0
            var read: [URL] = []
            exec("BEGIN;")
            for url in legacyReadings {
                guard fm.fileExists(atPath: url.path) else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                read.append(url)
                for line in text.split(separator: "\n") {
                    guard let s = HistoryReader.parse(line) else { continue }
                    if insertSampleUnsafe(s) { imported += 1 }
                }
            }
            exec("COMMIT;")
            // Only retire once data is safely in the table (covers a partial/failed
            // import). A file with no real rows is retired on a later launch once
            // the DB has rows (e.g. from live logging) so it doesn't linger forever.
            if hasSamples() {
                for url in read { retire(url); retiredAny = true }
            }
            if imported > 0 { Log.notice(.history, "imported \(imported) readings from CSV into SQLite") }
        }

        // Alerts (low-stakes — retire whenever the file was readable).
        if let alertsURL = legacyAlerts, fm.fileExists(atPath: alertsURL.path),
           let text = try? String(contentsOf: alertsURL, encoding: .utf8) {
            exec("BEGIN;")
            var imported = 0
            for line in text.split(separator: "\n") {
                guard let event = AlertLog.parse(line) else { continue }
                recordAlertUnsafe(message: event.message, at: event.time); imported += 1
            }
            exec("COMMIT;")
            retire(alertsURL); retiredAny = true
            if imported > 0 { Log.notice(.history, "imported \(imported) alerts from log into SQLite") }
        }
        return retiredAny
    }

    /// Whether the readings table holds any row — the gate for retiring (and
    /// thus eventually deleting) the migrated CSV, so the only copy of real data
    /// is never removed after a failed import.
    private func hasSamples() -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT EXISTS(SELECT 1 FROM samples);", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int64(stmt, 0) == 1
    }

    /// Rename an imported legacy file to `*.imported` and stamp it with the
    /// migration time, so the grace clock for auto-deletion starts now (a plain
    /// rename keeps the file's old timestamp, which could be months back).
    private func retire(_ url: URL) {
        let fm = FileManager.default
        let imported = url.appendingPathExtension("imported")
        try? fm.removeItem(at: imported)   // a prior, expired backup
        guard (try? fm.moveItem(at: url, to: imported)) != nil else { return }
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: imported.path)
    }

    /// Delete the imported legacy backups once they're older than the grace
    /// period — so a converted user's data home doesn't keep stale CSV/alert
    /// files around to confuse them. Runs every open; the file's own timestamp
    /// (stamped at migration in `retire`) is the clock.
    private func removeStaleImportedFiles() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Self.importedGracePeriod)
        let backups = (legacyReadings + [legacyAlerts].compactMap { $0 })
            .map { $0.appendingPathExtension("imported") }
        for url in backups {
            guard let modified = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fm.removeItem(at: url)
            Log.notice(.history, "removed migrated legacy file \(url.lastPathComponent)")
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

    private func recordAlertUnsafe(message: String, at time: Date) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO alerts (ts, message) VALUES (?,?);", -1, &stmt, nil) == SQLITE_OK
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
