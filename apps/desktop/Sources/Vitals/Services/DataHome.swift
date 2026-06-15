import Foundation

/// The single on-disk home for everything Vitals writes — the rolling history
/// log and user exports. Lives in a hidden folder in the user's home
/// (`~/.vitals`, or `~/.vitals-dev` for the Dev build) so the two channels never
/// share data and everything sits in one predictable place.
///
/// This is deliberately *not* `~/Library/Application Support` (the usual macOS
/// spot): a single dotfolder keeps the log and its exports together and easy to
/// find. The fan helper's privileged `/Library/Application Support/Vitals…`
/// directory is a separate, root-owned concern and is untouched by this.
enum DataHome {
    /// `~/.vitals` (Stable) or `~/.vitals-dev` (Dev). Resolved once.
    static let directory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let name = Channel.current.isDev ? ".vitals-dev" : ".vitals"
        return home.appendingPathComponent(name, isDirectory: true)
    }()

    static var historyFile: URL { directory.appendingPathComponent("history.csv") }
    static var historyPrevious: URL { directory.appendingPathComponent("history-previous.csv") }
    /// The developer/diagnostic log (JSONL), and its rotated predecessor.
    static var logFile: URL { directory.appendingPathComponent("vitals.log") }
    static var logPrevious: URL { directory.appendingPathComponent("vitals-previous.log") }
    /// Where user-initiated exports (CSV/JSON snapshots) are written.
    static var exportsDirectory: URL { directory.appendingPathComponent("exports", isDirectory: true) }

    /// Creates the home (and `exports/`) and migrates a pre-existing log out of
    /// the old Application Support location. Call once at launch, before any
    /// writing begins. Idempotent: once the legacy file is moved it's gone, so a
    /// second run does nothing.
    static func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        migrateLegacyLog(fm)
    }

    /// The log used to live in `~/Library/Application Support/Vitals/` and wasn't
    /// channel-isolated, so only Stable claims it; the throwaway Dev build starts
    /// fresh. Moves on the same volume, so it's an instant rename.
    private static func migrateLegacyLog(_ fm: FileManager) {
        guard !Channel.current.isDev else { return }
        let legacyDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vitals", isDirectory: true)
        for name in ["history.csv", "history-previous.csv"] {
            let old = legacyDir.appendingPathComponent(name)
            let new = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
            }
        }
    }
}
