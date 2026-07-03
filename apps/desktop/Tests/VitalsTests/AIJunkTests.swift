import Testing
import Foundation
@testable import Vitals

/// The AI-tool-junk scan must stay honest and safe: it lists nothing for a tool
/// that isn't installed, never touches a live session's fresh temp directory,
/// spares persistent memory, and only ever offers aged chat transcripts (files)
/// through the Trash. These lock those guarantees against a fixture home/tmp.
struct AIJunkTests {
    // MARK: Fixtures

    /// A throwaway home + tmp root, torn down after the test body runs.
    private final class Fixture {
        let fm = FileManager.default
        let home: URL
        let tmpRoot: URL

        init() throws {
            let base = fm.temporaryDirectory.appendingPathComponent("vitals-aijunk-\(UUID().uuidString)")
            home = base.appendingPathComponent("home")
            tmpRoot = base.appendingPathComponent("tmp")
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        }

        func destroy() { try? fm.removeItem(at: home.deletingLastPathComponent()) }

        @discardableResult
        func dir(_ relative: String, under root: URL? = nil, ageDays: Double? = nil) throws -> URL {
            let url = (root ?? home).appendingPathComponent(relative)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            if let ageDays { try touch(url, ageDays: ageDays) }
            return url
        }

        @discardableResult
        func file(_ relative: String, under root: URL? = nil, ageDays: Double = 0) throws -> URL {
            let url = (root ?? home).appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
            try touch(url, ageDays: ageDays)
            return url
        }

        func touch(_ url: URL, ageDays: Double) throws {
            let date = Date().addingTimeInterval(-ageDays * 86_400)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let fixture = try Fixture()
        defer { fixture.destroy() }
        try body(fixture)
    }

    private func paths(_ urls: [URL]) -> Set<String> {
        Set(urls.map { $0.standardizedFileURL.path })
    }

    // MARK: Detection

    @Test func undetectedToolsContributeNothing() throws {
        try withFixture { f in
            // A bare home with no AI tool directories.
            #expect(AIToolJunk.detectedTools(home: f.home).isEmpty)
            #expect(AIToolJunk.detectedTools(home: f.home).map(\.name).isEmpty)
            #expect(AIToolJunk.cacheItems(home: f.home, tmpRoot: f.tmpRoot, now: Date()).isEmpty)
            #expect(AIToolJunk.historyItems(home: f.home, now: Date()).isEmpty)
        }
    }

    @Test func detectionKeysOnTheToolDirectory() throws {
        try withFixture { f in
            try f.dir(".claude")
            let names = AIToolJunk.detectedTools(home: f.home).map(\.name)
            #expect(names == ["Claude Code"])
        }
    }

    // MARK: Temp working directories

    @Test func staleTmpSessionsIncludedFreshOnesExcluded() throws {
        try withFixture { f in
            try f.dir(".claude")  // detect Claude Code
            let sessionRoot = f.tmpRoot.appendingPathComponent("claude-\(getuid())")
            let old = try f.dir("stale", under: sessionRoot, ageDays: 2)     // > 24h → included
            let fresh = try f.dir("live", under: sessionRoot, ageDays: 0)    // live session → skipped

            let items = paths(AIToolJunk.cacheItems(home: f.home, tmpRoot: f.tmpRoot, now: Date()))
            #expect(items.contains(old.standardizedFileURL.path))
            #expect(!items.contains(fresh.standardizedFileURL.path))
        }
    }

    // MARK: Shell snapshots + file-history (live-session safety)

    @Test func shellSnapshotsAreListedByAgedContentsNotWholeDir() throws {
        try withFixture { f in
            try f.dir(".claude")
            let snaps = try f.dir(".claude/shell-snapshots")
            let stale = try f.file("snapshot-old.sh", under: snaps, ageDays: 3)   // > 24h → listed
            let fresh = try f.file("snapshot-live.sh", under: snaps, ageDays: 0)   // live session → spared

            let items = paths(AIToolJunk.cacheItems(home: f.home, tmpRoot: f.tmpRoot, now: Date()))
            #expect(items.contains(stale.standardizedFileURL.path))
            #expect(!items.contains(fresh.standardizedFileURL.path))
            // Never the whole directory — that would break a running session.
            #expect(!items.contains(snaps.standardizedFileURL.path))
        }
    }

    @Test func fileHistoryIsNeverOffered() throws {
        try withFixture { f in
            try f.dir(".claude")
            // Edit-recovery data, not a cache — never listed even when old.
            let history = try f.dir(".claude/file-history", ageDays: 60)
            try f.file("edit-123.json", under: history, ageDays: 60)

            let items = paths(AIToolJunk.cacheItems(home: f.home, tmpRoot: f.tmpRoot, now: Date()))
            #expect(!items.contains { $0.contains("file-history") })
        }
    }

    // MARK: Chat transcripts

    @Test func transcriptsAreExtensionAndAgeGated() throws {
        try withFixture { f in
            try f.dir(".claude")
            let projects = ".claude/projects/acme"
            let oldJSONL = try f.file("\(projects)/session-old.jsonl", ageDays: 40)   // included
            try f.file("\(projects)/session-new.jsonl", ageDays: 5)                   // too new
            try f.file("\(projects)/notes.txt", ageDays: 40)                          // wrong extension

            let items = paths(AIToolJunk.historyItems(home: f.home, now: Date()))
            #expect(items == [oldJSONL.standardizedFileURL.path])
        }
    }

    @Test func memoryAndHistoryLogAreNeverTranscripts() throws {
        try withFixture { f in
            try f.dir(".claude")
            let projects = ".claude/projects/acme"
            let realTranscript = try f.file("\(projects)/session.jsonl", ageDays: 60)
            // None of these may ever be offered, even though they're old:
            try f.file("\(projects)/memory/index.jsonl", ageDays: 60)   // inside a `memory` dir
            try f.file("\(projects)/memory/MEMORY.md", ageDays: 60)     // a MEMORY.md
            try f.file(".claude/history.jsonl", ageDays: 60)            // top-level history log

            let items = paths(AIToolJunk.historyItems(home: f.home, now: Date()))
            #expect(items == [realTranscript.standardizedFileURL.path])
        }
    }

    @Test func memoryGuardsAreCaseInsensitive() throws {
        try withFixture { f in
            try f.dir(".codex")
            let sessions = ".codex/sessions"
            // Codex's history scan has no extension filter, so this exercises the
            // name guards themselves rather than an extension mismatch.
            let realSession = try f.file("\(sessions)/session1.log", ageDays: 60)
            // Case variants of the guarded names — must be spared even though a
            // case-sensitive volume would treat them as distinct from "memory"/"MEMORY.md".
            try f.file("\(sessions)/Memory/index.jsonl", ageDays: 60)   // capital-M dir
            try f.file("\(sessions)/MeMoRy.MD", ageDays: 60)            // mixed-case MEMORY.md

            let items = paths(AIToolJunk.historyItems(home: f.home, now: Date()))
            #expect(items == [realSession.standardizedFileURL.path])
        }
    }

    // MARK: Version keep-newest

    @Test func versionKeepKeepsNewestAndSymlinkTarget() throws {
        try withFixture { f in
            try f.dir(".claude")
            let versions = try f.dir(".local/share/claude/versions")
            let v1 = try f.dir("1.0.0", under: versions, ageDays: 30)  // symlink target → kept
            let v2 = try f.dir("1.1.0", under: versions, ageDays: 20)  // stale → listed
            let v3 = try f.dir("1.2.0", under: versions, ageDays: 10)  // newest → kept

            // The active-version symlink `~/.local/bin/claude` → v1.
            let bin = try f.dir(".local/bin")
            try f.fm.createSymbolicLink(at: bin.appendingPathComponent("claude"), withDestinationURL: v1)

            let items = paths(AIToolJunk.cacheItems(home: f.home, tmpRoot: f.tmpRoot, now: Date()))
            #expect(items.contains(v2.standardizedFileURL.path))       // listed
            #expect(!items.contains(v1.standardizedFileURL.path))      // symlink target kept
            #expect(!items.contains(v3.standardizedFileURL.path))      // newest kept
        }
    }

    @Test func versionShapedNameRequiredMetadataFileNeverKeptOrListed() throws {
        try withFixture { f in
            try f.dir(".claude")
            let versions = try f.dir(".local/share/claude/versions")
            let v1 = try f.dir("1.0.0", under: versions, ageDays: 20)          // older version → listed
            let v2 = try f.dir("1.1.0", under: versions, ageDays: 10)          // newest version → kept
            // Newer than both versions, but not version-shaped: must never be
            // treated as the newest (which would shield v2.1.0 from listing)
            // and must never itself be listed.
            try f.file("manifest.json", under: versions, ageDays: 1)

            let items = paths(AIToolJunk.cacheItems(home: f.home, tmpRoot: f.tmpRoot, now: Date()))
            #expect(items.contains(v1.standardizedFileURL.path))
            #expect(!items.contains(v2.standardizedFileURL.path))
            #expect(!items.contains { $0.contains("manifest.json") })
        }
    }

    @Test func versionShapedSingleVersionAlongsideMetadataIsKept() throws {
        try withFixture { f in
            try f.dir(".claude")
            let versions = try f.dir(".local/share/claude/versions")
            let onlyVersion = try f.dir("2.0.14", under: versions, ageDays: 5)
            try f.file("manifest.json", under: versions, ageDays: 1)
            try f.file(".DS_Store", under: versions, ageDays: 1)

            let items = paths(AIToolJunk.cacheItems(home: f.home, tmpRoot: f.tmpRoot, now: Date()))
            #expect(!items.contains(onlyVersion.standardizedFileURL.path))
            #expect(!items.contains { $0.contains("manifest.json") || $0.contains(".DS_Store") })
        }
    }

    // MARK: Category wiring

    @Test func aiCachesIsQuickNonAdminNonDestructive() {
        let kind = CleanupCategory.Kind.aiCaches
        #expect(kind.minimumDepth == .quick)
        #expect(!kind.requiresAdmin)
        #expect(!kind.isDestructive)
        #expect(!kind.movesToTrash)
    }

    @Test func aiHistoryIsDeepNonAdminDestructiveTrash() {
        let kind = CleanupCategory.Kind.aiHistory
        #expect(kind.minimumDepth == .deep)
        #expect(!kind.requiresAdmin)
        #expect(kind.isDestructive)
        #expect(kind.movesToTrash)
    }

    @Test func onlyAIHistoryMovesToTrash() {
        let trashed = CleanupCategory.Kind.allCases.filter(\.movesToTrash)
        #expect(trashed == [.aiHistory])
    }

    @Test func quickScanStillHasNoAdminCategories() {
        // Adding an AI card must not introduce an admin category into Quick.
        #expect(DiskCleaner.scan(depth: .quick).allSatisfy { !$0.kind.requiresAdmin })
    }
}
