import Foundation

/// The single on-disk home for everything Vitals writes: `~/.vitals`, or
/// `~/.vitals-nightly` / `~/.vitals-dev`, so the channels never share data.
///
///   ~/.vitals/
///     logs/      the diagnostic log and crash bookkeeping
///     history/   the readings + alerts database
///     exports/   files you export by hand
enum DataHome {
    static let directory: URL = {
        // Only a packaged app owns real data. Unbundled processes (the test
        // runner, `swift run`, `--probe`) would otherwise default to Stable's
        // folder and write into the user's daily-driver history.
        guard Bundle.main.bundleIdentifier != nil else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("vitals-unbundled", isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(Channel.current.dataDirSuffix, isDirectory: true)
    }()

    static var logsDirectory: URL { directory.appendingPathComponent("logs", isDirectory: true) }
    static var historyDirectory: URL { directory.appendingPathComponent("history", isDirectory: true) }
    static var exportsDirectory: URL { directory.appendingPathComponent("exports", isDirectory: true) }

    /// SQLite keeps its `-wal`/`-shm` sidecars next to it.
    static var historyDatabaseFile: URL { historyDirectory.appendingPathComponent("history.sqlite3") }
    /// The diagnostic log (JSONL) and its rotated predecessor.
    static var logFile: URL { logsDirectory.appendingPathComponent("vitals.log") }
    static var logPrevious: URL { logsDirectory.appendingPathComponent("vitals-previous.log") }
    static var crashAckFile: URL { logsDirectory.appendingPathComponent("crash-ack") }

    /// Creates the home and its subfolders. Call once at launch, before any writes.
    static func prepare() {
        do {
            for subdir in [logsDirectory, historyDirectory, exportsDirectory] {
                try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            }
        } catch {
            // Cascades: with no data home, history/log/export writes all fail.
            Log.error(.app, "couldn't create data home at \(directory.path)", error: error)
        }
    }
}
