import Foundation
import SQLite3

final class ActivityStore: @unchecked Sendable {
    struct Event: Identifiable, Equatable, Sendable {
        let id: Int64
        let at: Date
        let source: String
        let level: String
        let kind: String
        let deviceId: String?
        let connectionId: String?
        let rpc: String?
        let commandId: String?
        let durationMs: Double?
        let data: String
    }

    struct Frame: Identifiable, Equatable, Sendable {
        let id: Int64
        let at: Date
        let direction: String
        let method: String?
        let tag: String
        let bytes: Int
    }

    struct Filter: Equatable, Sendable {
        var source: String?
        var level: String?
        var text = ""
    }

    struct Summary: Equatable, Sendable {
        var events = 0
        var errors = 0
        var connections = 0
        var frames = 0
    }

    private let queue = DispatchQueue(label: "vitals.activity.read")
    private var db: OpaquePointer?
    private let file: URL

    init(file: URL) { self.file = file }

    deinit { if let db { sqlite3_close(db) } }

    private func connection() -> OpaquePointer? {
        if let db { return db }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        sqlite3_exec(handle, "PRAGMA query_only = ON; PRAGMA busy_timeout = 2000;", nil, nil, nil)
        db = handle
        return handle
    }

    func dataVersion() -> Int64 {
        queue.sync {
            guard let db = connection() else { return -1 }
            return scalar(db, "PRAGMA data_version")
        }
    }

    func events(filter: Filter, afterSeq: Int64 = 0, limit: Int = 300) -> [Event] {
        queue.sync {
            guard let db = connection() else { return [] }
            var clauses = ["seq > ?1"]
            if filter.source != nil { clauses.append("source = ?2") }
            if filter.level != nil { clauses.append("level = ?3") }
            if !filter.text.isEmpty { clauses.append("(kind LIKE ?4 OR data_json LIKE ?4 OR rpc LIKE ?4)") }
            let sql = """
            SELECT seq, at, source, level, kind, device_id, connection_id, rpc, command_id, duration_ms, data_json
            FROM events WHERE \(clauses.joined(separator: " AND ")) ORDER BY seq DESC LIMIT ?5
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, afterSeq)
            bind(stmt, 2, filter.source)
            bind(stmt, 3, filter.level)
            bind(stmt, 4, filter.text.isEmpty ? nil : "%\(filter.text)%")
            sqlite3_bind_int(stmt, 5, Int32(limit))
            var rows: [Event] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(Event(
                    id: sqlite3_column_int64(stmt, 0),
                    at: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 1)) / 1000),
                    source: text(stmt, 2) ?? "",
                    level: text(stmt, 3) ?? "",
                    kind: text(stmt, 4) ?? "",
                    deviceId: text(stmt, 5),
                    connectionId: text(stmt, 6),
                    rpc: text(stmt, 7),
                    commandId: text(stmt, 8),
                    durationMs: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 9),
                    data: text(stmt, 10) ?? "{}"
                ))
            }
            return rows
        }
    }

    func frames(connectionId: String, limit: Int = 500) -> [Frame] {
        queue.sync {
            guard let db = connection() else { return [] }
            var stmt: OpaquePointer?
            let sql = "SELECT seq, at, dir, method, tag, bytes FROM frames WHERE connection_id = ?1 ORDER BY seq DESC LIMIT ?2"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, connectionId)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            var rows: [Frame] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(Frame(
                    id: sqlite3_column_int64(stmt, 0),
                    at: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 1)) / 1000),
                    direction: text(stmt, 2) ?? "",
                    method: text(stmt, 3),
                    tag: text(stmt, 4) ?? "",
                    bytes: Int(sqlite3_column_int64(stmt, 5))
                ))
            }
            return rows
        }
    }

    /// A phone the gateway turned away on Wi-Fi, grouped by address and reason. The gateway logs
    /// each pair at most once a minute, so `first` and `last` bound the attempts rather than count them.
    struct Refusal: Identifiable, Equatable, Sendable {
        var id: String { "\(address) \(why)" }
        let address: String
        let why: String
        let client: String?
        let first: Date
        let last: Date
    }

    /// The latest connection each device opened.
    struct Visit: Identifiable, Equatable, Sendable {
        var id: String { deviceId }
        let deviceId: String
        let at: Date
        let client: String?
        let overWifi: Bool
    }

    struct Attempts: Equatable, Sendable {
        var refusals: [Refusal] = []
        var visits: [Visit] = []
        /// When any phone last opened a connection, however long ago.
        var lastReached: Date?
    }

    func attempts(since: Date) -> Attempts {
        queue.sync {
            guard let db = connection() else { return Attempts() }
            let from = Int64(since.timeIntervalSince1970 * 1000)
            var result = Attempts()
            let refusals = """
            SELECT json_extract(data_json, '$.address'), json_extract(data_json, '$.why'), max(json_extract(data_json, '$.client')), min(at), max(at)
            FROM events WHERE kind = 'lan.refused' AND at >= ?1
            GROUP BY 1, 2 ORDER BY 5 DESC LIMIT 8
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, refusals, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, from)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    result.refusals.append(Refusal(
                        address: text(stmt, 0) ?? "unknown",
                        why: text(stmt, 1) ?? "",
                        client: text(stmt, 2),
                        first: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 3)) / 1000),
                        last: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 4)) / 1000)
                    ))
                }
            }
            sqlite3_finalize(stmt)
            stmt = nil
            // SQLite returns the other columns from the row holding max(opened_at).
            let visits = """
            SELECT device_id, max(opened_at), client_version, ts_login FROM connections
            WHERE opened_at >= ?1 GROUP BY device_id ORDER BY 2 DESC LIMIT 8
            """
            if sqlite3_prepare_v2(db, visits, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, from)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    result.visits.append(Visit(
                        deviceId: text(stmt, 0) ?? "",
                        at: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 1)) / 1000),
                        client: text(stmt, 2),
                        overWifi: text(stmt, 3) == "wifi"
                    ))
                }
            }
            sqlite3_finalize(stmt)
            let last = scalar(db, "SELECT coalesce(max(opened_at), 0) FROM connections")
            result.lastReached = last > 0 ? Date(timeIntervalSince1970: Double(last) / 1000) : nil
            return result
        }
    }

    func summary(since: Date) -> Summary {
        queue.sync {
            guard let db = connection() else { return Summary() }
            let from = Int64(since.timeIntervalSince1970 * 1000)
            return Summary(
                events: Int(scalar(db, "SELECT coalesce(sum(count), 0) FROM rollups_minute WHERE minute >= \(from)")),
                errors: Int(scalar(db, "SELECT coalesce(sum(errors), 0) FROM rollups_minute WHERE minute >= \(from)")),
                connections: Int(scalar(db, "SELECT count(*) FROM connections WHERE opened_at >= \(from)")),
                frames: Int(scalar(db, "SELECT count(*) FROM frames WHERE at >= \(from)"))
            )
        }
    }

    private func scalar(_ db: OpaquePointer, _ sql: String) -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func text(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: raw)
    }
}
