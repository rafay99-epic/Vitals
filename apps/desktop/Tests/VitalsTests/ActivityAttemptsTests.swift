import Foundation
import SQLite3
import Testing
@testable import Vitals

/// "Phones that tried to connect" groups the gateway's Wi-Fi refusals by address and reason,
/// and keeps only the latest connection per device.
struct ActivityAttemptsTests {
    @Test func groupsRefusalsAndKeepsTheLatestVisit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: file) }
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let sql = """
        CREATE TABLE events (seq INTEGER PRIMARY KEY, at INTEGER, kind TEXT, data_json TEXT);
        CREATE TABLE connections (id TEXT PRIMARY KEY, device_id TEXT, opened_at INTEGER, ts_login TEXT, client_version TEXT);
        INSERT INTO events (at, kind, data_json) VALUES
          (\(now - 120_000), 'lan.refused', '{"address":"192.168.0.33","why":"unknown phone key","client":"0.181"}'),
          (\(now - 60_000), 'lan.refused', '{"address":"192.168.0.33","why":"unknown phone key","client":"0.181"}'),
          (\(now - 30_000), 'lan.refused', '{"address":"192.168.0.40","why":"other protocol"}'),
          (\(now - 10_000), 'ws.opened', '{}');
        INSERT INTO connections VALUES
          ('a', 'phone', \(now - 50_000), 'wifi', '0.180'),
          ('b', 'phone', \(now - 5_000), 'owner@example.com', '0.181');
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let attempts = ActivityStore(file: file).attempts(since: Date().addingTimeInterval(-3_600))

        #expect(attempts.refusals.map(\.address) == ["192.168.0.40", "192.168.0.33"])
        let repeated = try #require(attempts.refusals.last)
        #expect(repeated.why == "unknown phone key")
        #expect(repeated.client == "0.181")
        #expect(repeated.last.timeIntervalSince(repeated.first) > 59)
        #expect(attempts.visits.count == 1)
        #expect(attempts.visits.first?.client == "0.181")
        #expect(attempts.visits.first?.overWifi == false)
        #expect(attempts.lastReached != nil)
    }
}
