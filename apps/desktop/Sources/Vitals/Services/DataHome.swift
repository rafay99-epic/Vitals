import Foundation

/// The single on-disk home for everything Vitals writes. Lives in a hidden
/// folder in the user's home (`~/.vitals`, or `~/.vitals-nightly` / `~/.vitals-dev`
/// for those channels) so the channels never share data and everything sits in
/// one predictable place.
///
/// Organised into a small set of self-describing subfolders so the home is
/// legible at a glance — open `~/.vitals` and the structure explains itself:
///
///   ~/.vitals/
///     config/    — your settings, mirrored as readable JSON (config.json)
///     logs/      — the diagnostic log, alert log, and crash bookkeeping
///     history/   — the rolling readings CSV
///     exports/   — files you export by hand
///
/// This is deliberately *not* `~/Library/Application Support` (the usual macOS
/// spot): a single dotfolder keeps everything together and easy to find. The fan
/// helper's privileged `/Library/Application Support/Vitals…` directory is a
/// separate, root-owned concern and is untouched by this.
enum DataHome {
    /// `~/.vitals` (Stable), `~/.vitals-nightly`, or `~/.vitals-dev`. Resolved once.
    static let directory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(Channel.current.dataDirSuffix, isDirectory: true)
    }()

    // MARK: Subfolders

    /// Settings, mirrored as readable JSON so they survive updates/reinstalls.
    static var configDirectory: URL { directory.appendingPathComponent("config", isDirectory: true) }
    /// The diagnostic log, the alert log, and crash bookkeeping.
    static var logsDirectory: URL { directory.appendingPathComponent("logs", isDirectory: true) }
    /// The rolling readings CSV (and its rotated predecessor).
    static var historyDirectory: URL { directory.appendingPathComponent("history", isDirectory: true) }
    /// Files the user exports by hand (CSV/JSON snapshots, problem-report logs).
    static var exportsDirectory: URL { directory.appendingPathComponent("exports", isDirectory: true) }

    /// Every subfolder, in creation order.
    private static var subdirectories: [URL] {
        [configDirectory, logsDirectory, historyDirectory, exportsDirectory]
    }

    // MARK: Files

    static var configFile: URL { configDirectory.appendingPathComponent("config.json") }
    static var historyFile: URL { historyDirectory.appendingPathComponent("history.csv") }
    static var historyPrevious: URL { historyDirectory.appendingPathComponent("history-previous.csv") }
    /// The developer/diagnostic log (JSONL), and its rotated predecessor.
    static var logFile: URL { logsDirectory.appendingPathComponent("vitals.log") }
    static var logPrevious: URL { logsDirectory.appendingPathComponent("vitals-previous.log") }
    /// The append-only alert log and the crash-acknowledgement marker.
    static var alertsFile: URL { logsDirectory.appendingPathComponent("alerts.log") }
    static var crashAckFile: URL { logsDirectory.appendingPathComponent("crash-ack") }

    // MARK: Lifecycle

    /// Creates the home and its subfolders, then migrates data from older layouts
    /// into them. Call once at launch, before any writing begins. Idempotent —
    /// once a file is moved it's gone, so a second run does nothing.
    static func prepare() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            for subdir in subdirectories {
                try fm.createDirectory(at: subdir, withIntermediateDirectories: true)
            }
        } catch {
            // Cascades: with no data home, history/log/export writes all fail.
            Log.error(.app, "couldn't create data home at \(directory.path)", error: error)
        }
        migrateLegacyAppSupport(fm)
        migrateFlatLayout(fm)
    }

    /// The history CSV used to live in `~/Library/Application Support/Vitals/` and
    /// wasn't channel-isolated, so only Stable claims it; the Nightly and Dev
    /// builds start fresh. Moves on the same volume, so it's an instant rename.
    private static func migrateLegacyAppSupport(_ fm: FileManager) {
        guard Channel.current == .stable else { return }
        let legacyDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vitals", isDirectory: true)
        guard fm.fileExists(atPath: legacyDir.path) else { return }

        // The only data that ever lived here was the readings CSV.
        let moves = [("history.csv", historyFile), ("history-previous.csv", historyPrevious)]
        let migrated = moves.reduce(0) { count, item in
            count + (move(fm, from: legacyDir.appendingPathComponent(item.0), to: item.1) ? 1 : 0)
        }
        if migrated > 0 {
            Log.notice(.history, "migrated \(migrated) file(s) from ~/Library/Application Support/Vitals")
        }

        // Tidy up: once the legacy folder holds nothing but cruft (a stray
        // .DS_Store), remove the husk so it doesn't linger. If any real file
        // remains — something we didn't expect — leave it strictly alone.
        if let leftovers = try? fm.contentsOfDirectory(atPath: legacyDir.path),
           leftovers.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(at: legacyDir)
        }
    }

    /// Earlier versions wrote everything flat in `~/.vitals/`. Move those files
    /// into the new subfolders so an updating user keeps their data.
    private static func migrateFlatLayout(_ fm: FileManager) {
        let moves: [(String, URL)] = [
            ("history.csv", historyFile),
            ("history-previous.csv", historyPrevious),
            ("vitals.log", logFile),
            ("vitals-previous.log", logPrevious),
            ("alerts.log", alertsFile),
            ("crash-ack", crashAckFile),
            ("config.json", configFile),
        ]
        for (name, new) in moves {
            move(fm, from: directory.appendingPathComponent(name), to: new)
        }
    }

    /// Moves `old` to `new` only when `old` exists and `new` doesn't — so a
    /// half-finished migration never clobbers newer data. Returns whether it
    /// actually moved anything.
    @discardableResult
    private static func move(_ fm: FileManager, from old: URL, to new: URL) -> Bool {
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return false }
        do {
            try fm.moveItem(at: old, to: new)
            return true
        } catch {
            Log.notice(.app, "couldn't migrate \(old.lastPathComponent) into the data home", error: error)
            return false
        }
    }
}
