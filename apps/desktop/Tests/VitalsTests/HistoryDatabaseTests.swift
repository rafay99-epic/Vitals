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

    private func sample(_ secondsAgo: TimeInterval, now: Date, gpuTemp: Double? = nil,
                        fanRPM: Double? = nil, battery: Double? = nil,
                        netIn: Double? = nil, netOut: Double? = nil,
                        diskRead: Double? = nil, diskWrite: Double? = nil,
                        socWatts: Double? = nil, batteryWatts: Double? = nil) -> HistorySample {
        HistorySample(
            time: now.addingTimeInterval(-secondsAgo),
            avgTemp: 45.5, hottestTemp: 52.0, gpuTemp: gpuTemp, fanRPM: fanRPM,
            cpuUsage: 12.3, memoryGB: 10.4, thermalState: "Nominal",
            batteryPercent: battery, gpuUsage: nil, gpuMemoryGB: nil,
            netInBps: netIn, netOutBps: netOut,
            diskReadBps: diskRead, diskWriteBps: diskWrite,
            socWatts: socWatts, batteryWatts: batteryWatts)
    }

    @Test func roundTripsRowsAndOptionals() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        db.insert(sample(20, now: now, gpuTemp: nil, fanRPM: 1200, battery: 87,
                         netIn: 125_000, netOut: 34_000, diskRead: 52_000_000, diskWrite: 9_500_000))

        let rows = db.samples(range: .all, now: now, maxPoints: 600)
        #expect(rows.count == 1)
        let r = try #require(rows.first)
        #expect(r.avgTemp == 45.5)
        #expect(r.gpuTemp == nil)          // NULL column → nil, not 0
        #expect(r.fanRPM == 1200)
        #expect(r.batteryPercent == 87)
        #expect(r.thermalState == "Nominal")
        #expect(r.netInBps == 125_000)
        #expect(r.netOutBps == 34_000)
        #expect(r.diskReadBps == 52_000_000)
        #expect(r.diskWriteBps == 9_500_000)
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

    @Test func dedupsIdenticalAlerts() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        db.recordAlert(message: "same", at: t)
        db.recordAlert(message: "same", at: t)        // identical (ts, message) → ignored
        db.recordAlert(message: "different", at: t)   // same ts, new message → kept
        #expect(db.recentAlerts(limit: 10).count == 2)
    }

    /// The schema's first migration: a database created by v1 (no network
    /// columns, `user_version=1`) must gain the columns in place — old rows keep
    /// their data and read back honest nil network rates, new rows carry values.
    @Test func migratesV1DatabaseInPlace() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()

        // Build a genuine v1 file by hand: the exact pre-network schema, one row,
        // stamped user_version=1 — what every existing install has on disk.
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let oldTs = Int64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)
        let v1 = """
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
        INSERT INTO samples (ts, avg_cpu, hottest_cpu, cpu_usage, memory_gb, thermal_state)
            VALUES (\(oldTs), 45.5, 52.0, 12.3, 10.4, 'Nominal');
        PRAGMA user_version=1;
        """
        #expect(sqlite3_exec(raw, v1, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(raw)

        let db = HistoryDatabase(file: url)
        db.waitUntilReady()
        db.insert(sample(20, now: now, netIn: 125_000, netOut: 34_000))

        let rows = db.samples(range: .all, now: now, maxPoints: 600)
        #expect(rows.count == 2)                       // the v1 row survived
        #expect(rows.first?.avgTemp == 45.5)
        #expect(rows.first?.netInBps == nil)           // pre-migration row: honest nil
        #expect(rows.last?.netInBps == 125_000)        // post-migration row: logged
        #expect(rows.last?.netOutBps == 34_000)
    }

    /// The schema's second migration: a database created by v2 (network
    /// columns present, but no disk columns, `user_version=2`) must gain the
    /// disk columns in place — old rows keep their data and read back honest
    /// nil disk rates, new rows carry values.
    @Test func migratesV2DatabaseInPlace() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()

        // Build a genuine v2 file by hand: the exact pre-disk schema, one row,
        // stamped user_version=2 — what every network-era install has on disk.
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let oldTs = Int64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)
        let v2 = """
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
            gpu_mem_gb    REAL,
            net_in_bps    REAL,
            net_out_bps   REAL
        );
        INSERT INTO samples (ts, avg_cpu, hottest_cpu, cpu_usage, memory_gb, thermal_state, net_in_bps, net_out_bps)
            VALUES (\(oldTs), 45.5, 52.0, 12.3, 10.4, 'Nominal', 125000, 34000);
        PRAGMA user_version=2;
        """
        #expect(sqlite3_exec(raw, v2, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(raw)

        let db = HistoryDatabase(file: url)
        db.waitUntilReady()
        db.insert(sample(20, now: now, netIn: 125_000, netOut: 34_000,
                         diskRead: 52_000_000, diskWrite: 9_500_000))

        let rows = db.samples(range: .all, now: now, maxPoints: 600)
        #expect(rows.count == 2)                       // the v2 row survived
        #expect(rows.first?.avgTemp == 45.5)
        #expect(rows.first?.netInBps == 125_000)       // pre-migration row kept its network reading
        #expect(rows.first?.diskReadBps == nil)        // pre-migration row: honest nil
        #expect(rows.first?.diskWriteBps == nil)
        #expect(rows.last?.diskReadBps == 52_000_000)  // post-migration row: logged
        #expect(rows.last?.diskWriteBps == 9_500_000)
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

    // MARK: v4 — power columns + per-app energy

    @Test func roundTripsPowerColumns() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        db.insert(sample(20, now: now, socWatts: 14.2, batteryWatts: -8.5))

        let r = try #require(db.samples(range: .all, now: now, maxPoints: 600).first)
        #expect(r.socWatts == 14.2)
        #expect(r.batteryWatts == -8.5)
    }

    /// An older database created at schema v3 (no soc_watts/battery_watts, no
    /// app_energy table) must migrate cleanly on open and then accept v4 rows.
    @Test func migratesV3DatabaseToV4() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()   // real now, so the retention prune at open keeps these rows

        // Build a minimal v3 `samples` table by hand (a recent row so it survives prune).
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let oldTs = Int64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1000)
        let v3 = """
        CREATE TABLE samples (
          id INTEGER PRIMARY KEY, ts INTEGER NOT NULL UNIQUE,
          avg_cpu REAL NOT NULL, hottest_cpu REAL NOT NULL, gpu_temp REAL, fan_rpm REAL,
          cpu_usage REAL NOT NULL, memory_gb REAL NOT NULL, thermal_state TEXT NOT NULL,
          battery_pct REAL, gpu_usage REAL, gpu_mem_gb REAL,
          net_in_bps REAL, net_out_bps REAL, disk_read_bps REAL, disk_write_bps REAL);
        INSERT INTO samples (ts, avg_cpu, hottest_cpu, cpu_usage, memory_gb, thermal_state)
          VALUES (\(oldTs), 40, 50, 10, 8, 'Nominal');
        PRAGMA user_version=3;
        """
        #expect(sqlite3_exec(raw, v3, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(raw)

        // Open with the current code → migration adds the new columns + table.
        let db = HistoryDatabase(file: url)
        db.insert(sample(0, now: now, socWatts: 12.0, batteryWatts: -5.0))
        db.appendAppEnergy([.init(bundleID: "com.x", name: "X", avgWatts: 3.0,
                                  cpuPercent: 20, wakeupsPerSec: 100, preventsSleep: true)], at: now)
        db.waitUntilReady()

        let rows = db.samples(range: .all, now: now, maxPoints: 600)
        #expect(rows.count == 2)                                // old row survived, new row added
        #expect(rows.contains { $0.socWatts == 12.0 })          // v4 column readable
        var appRows: [(Date, HistoryDatabase.AppEnergyRow)] = []
        db.forEachAppEnergy { appRows.append(($0, $1)) }
        #expect(appRows.count == 1)                             // app_energy table created + written
        #expect(appRows.first?.1.preventsSleep == true)
    }

    @Test func appEnergyRoundTripsAndThrottles() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date()   // real now, so the on-write retention prune keeps these rows
        let batch: [HistoryDatabase.AppEnergyRow] = [
            .init(bundleID: "com.a", name: "A", avgWatts: 2.5, cpuPercent: 30, wakeupsPerSec: 50, preventsSleep: false),
            .init(bundleID: nil, name: "daemon", avgWatts: nil, cpuPercent: 1, wakeupsPerSec: 5, preventsSleep: true),
        ]
        db.appendAppEnergy(batch, at: now)
        // A second batch 30s later is inside the 60s throttle → dropped.
        db.appendAppEnergy(batch, at: now.addingTimeInterval(30))
        db.waitUntilReady()

        var rows: [HistoryDatabase.AppEnergyRow] = []
        db.forEachAppEnergy { _, row in rows.append(row) }
        #expect(rows.count == 2)                            // only the first batch landed
        #expect(rows.contains { $0.avgWatts == nil && $0.name == "daemon" })   // honest nil watts
        #expect(rows.contains { $0.bundleID == "com.a" && $0.avgWatts == 2.5 })
    }

    @Test func appEnergyRetentionPrunesOnWrite() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let db = HistoryDatabase(file: url)
        let now = Date()
        // A batch stamped 20 days ago is past the 14-day app-energy retention; the
        // on-write prune must drop it rather than waiting for the next app open.
        db.appendAppEnergy([.init(bundleID: nil, name: "Old", avgWatts: 1, cpuPercent: 1,
                                  wakeupsPerSec: 1, preventsSleep: false)], at: now.addingTimeInterval(-20 * 86_400))
        db.appendAppEnergy([.init(bundleID: nil, name: "New", avgWatts: 1, cpuPercent: 1,
                                  wakeupsPerSec: 1, preventsSleep: false)], at: now)
        db.waitUntilReady()

        var names: [String] = []
        db.forEachAppEnergy { _, row in names.append(row.name) }
        #expect(names == ["New"])   // old batch pruned by the retention window
    }
}
