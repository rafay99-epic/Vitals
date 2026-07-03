import Testing
import Foundation
@testable import Vitals

/// The "Large & Old Files" review surface: it lists big/old personal files
/// honestly, conservatively flags only obvious Downloads junk as "Suggested",
/// and — because these are the user's own files — only ever deletes to the
/// Trash. These tests lock the size/age filtering, the narrow suggestion rules,
/// the walk's safety (symlinks, hidden files, packages, depth/limit), and the
/// recoverable-deletion contract.
struct LargeFileScannerTests {
    // MARK: Fixtures

    /// A throwaway home under the temp dir, cleaned up on scope exit.
    private final class TempHome {
        let url: URL
        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitals-largefile-\(UUID().uuidString)", isDirectory: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    @discardableResult
    private func makeFile(_ home: URL, _ relative: String, bytes: Int, ageDays: Int? = nil) throws -> URL {
        let fm = FileManager.default
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        if let ageDays {
            let date = Date().addingTimeInterval(-Double(ageDays) * 86_400)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    private let big = 2_000_000       // ~2 MB, comfortably over the thresholds below
    private func anySize(min: UInt64 = 1_000_000) -> LargeFileScanner.Filter {
        .init(minSizeBytes: min, minAgeDays: nil)
    }

    // MARK: Threshold & age filtering

    @Test func thresholdExcludesSmallIncludesLarge() throws {
        let home = TempHome()
        try makeFile(home.url, "Documents/big.bin", bytes: big)
        try makeFile(home.url, "Documents/small.txt", bytes: 100)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Documents")],
                                          filter: anySize(), home: home.url)
        #expect(items.map(\.name) == ["big.bin"])
    }

    @Test func ageFilterExcludesNewerFiles() throws {
        let home = TempHome()
        try makeFile(home.url, "Documents/old.bin", bytes: big, ageDays: 200)
        try makeFile(home.url, "Documents/new.bin", bytes: big, ageDays: 2)

        let items = LargeFileScanner.scan(
            roots: [home.url.appendingPathComponent("Documents")],
            filter: .init(minSizeBytes: 1_000_000, minAgeDays: 30), home: home.url)
        #expect(items.map(\.name) == ["old.bin"])
    }

    // MARK: Suggestion rules (test-locked, conservative)

    @Test func bigMovieIsListedButNeverSuggested() throws {
        let home = TempHome()
        try makeFile(home.url, "Movies/huge.mp4", bytes: big)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Movies")],
                                          filter: anySize(), home: home.url)
        #expect(items.count == 1)
        #expect(items.first?.name == "huge.mp4")
        #expect(items.first?.isSuggested == false)
    }

    /// The suggestion rules are pure functions of path + age, so exercise every
    /// branch directly with a fixed clock — no filesystem needed.
    @Test func suggestionRulesAreExactlyThese() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func dl(_ n: String) -> URL { home.appendingPathComponent("Downloads/\(n)") }
        func age(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }
        func s(_ url: URL, _ modified: Date?) -> Bool {
            LargeFileScanner.isSuggested(url: url, modified: modified, home: home, now: now)
        }

        // (a) installers/images > 90 days
        #expect(s(dl("app.dmg"), age(100)))
        #expect(s(dl("app.pkg"), age(200)))
        #expect(!s(dl("app.dmg"), age(10)))        // fresh
        #expect(!s(dl("app.dmg"), nil))            // unknown age → never
        // (b) dead partial downloads, any age
        #expect(s(dl("movie.crdownload"), now))
        #expect(s(dl("file.part"), nil))
        #expect(s(dl("thing.download"), age(1)))
        // (c) archives > 180 days
        #expect(s(dl("bundle.zip"), age(200)))
        #expect(!s(dl("bundle.zip"), age(100)))    // 100 < 180
        #expect(s(dl("nested/deep/old.tar"), age(365)))
        // Downloads-only: the same stale archive elsewhere is never suggested.
        #expect(!s(home.appendingPathComponent("Documents/bundle.zip"), age(400)))
        // Unlisted extension in Downloads: never suggested.
        #expect(!s(dl("clip.mp4"), age(999)))
    }

    @Test func oldDmgInDownloadsSuggestedFreshNot() throws {
        let home = TempHome()
        try makeFile(home.url, "Downloads/old.dmg", bytes: big, ageDays: 120)
        try makeFile(home.url, "Downloads/new.dmg", bytes: big, ageDays: 3)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Downloads")],
                                          filter: anySize(), home: home.url)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.isSuggested) })
        #expect(byName["old.dmg"] == true)
        #expect(byName["new.dmg"] == false)
    }

    @Test func crdownloadSuggestedRegardlessOfAge() throws {
        let home = TempHome()
        try makeFile(home.url, "Downloads/partial.crdownload", bytes: big, ageDays: 0)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Downloads")],
                                          filter: anySize(), home: home.url)
        #expect(items.first(where: { $0.name == "partial.crdownload" })?.isSuggested == true)
    }

    @Test func oldZipInDocumentsNotSuggested() throws {
        let home = TempHome()
        try makeFile(home.url, "Documents/archive.zip", bytes: big, ageDays: 400)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Documents")],
                                          filter: anySize(), home: home.url)
        #expect(items.first(where: { $0.name == "archive.zip" })?.isSuggested == false)
    }

    // MARK: Walk safety

    @Test func symlinksAreSkipped() throws {
        let home = TempHome()
        let real = try makeFile(home.url, "Documents/real.bin", bytes: big)
        let link = home.url.appendingPathComponent("Documents/link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Documents")],
                                          filter: anySize(), home: home.url)
        #expect(items.map(\.name) == ["real.bin"])   // the symlink is never listed
    }

    @Test func hiddenFilesAreSkipped() throws {
        let home = TempHome()
        try makeFile(home.url, "Documents/.secret.bin", bytes: big)
        try makeFile(home.url, "Documents/visible.bin", bytes: big)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Documents")],
                                          filter: anySize(), home: home.url)
        #expect(items.map(\.name) == ["visible.bin"])
    }

    @Test func packageIsOneItemNotDescended() throws {
        let home = TempHome()
        try makeFile(home.url, "Documents/Foo.app/Contents/a.bin", bytes: big)
        try makeFile(home.url, "Documents/Foo.app/Contents/MacOS/b.bin", bytes: big)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Documents")],
                                          filter: anySize(), home: home.url)
        // The bundle is a single item; its innards are never surfaced separately.
        #expect(items.map(\.name) == ["Foo.app"])
        #expect((items.first?.sizeBytes ?? 0) >= UInt64(2 * big))
    }

    @Test func resultsAreSizeDescendingAndCapped() throws {
        let home = TempHome()
        // Distinct sizes so ordering is unambiguous.
        try makeFile(home.url, "Documents/a.bin", bytes: 5_000_000)
        try makeFile(home.url, "Documents/b.bin", bytes: 4_000_000)
        try makeFile(home.url, "Documents/c.bin", bytes: 3_000_000)
        try makeFile(home.url, "Documents/d.bin", bytes: 2_000_000)

        let items = LargeFileScanner.scan(roots: [home.url.appendingPathComponent("Documents")],
                                          filter: anySize(), home: home.url, limit: 2)
        #expect(items.map(\.name) == ["a.bin", "b.bin"])            // top 2 only
        #expect(items.map(\.sizeBytes) == items.map(\.sizeBytes).sorted(by: >))
    }

    @Test func defaultRootsAreExistingContentFolders() throws {
        let home = TempHome()
        try FileManager.default.createDirectory(
            at: home.url.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.url.appendingPathComponent("Pictures"), withIntermediateDirectories: true)
        // Movies/Music/Documents/Desktop don't exist → excluded.

        let names = Set(LargeFileScanner.defaultRoots(home: home.url).map(\.lastPathComponent))
        #expect(names == ["Downloads", "Pictures"])
    }

    // MARK: Trash-only deletion

    /// Trashing must move the file out of its original path and credit exactly
    /// its bytes. Run against a file on the boot volume (the temp dir) so
    /// `trashItem` is available; if a CI volume disallows it, the failure is
    /// recorded rather than a spurious pass — either way the assertion holds.
    @Test func trashRemovesOriginalAndCreditsBytes() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("vitals-trash-\(UUID().uuidString).bin")
        try Data(count: 1_234_567).write(to: url)
        let size = UInt64((try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        let item = LargeFileScanner.Item(url: url, name: url.lastPathComponent,
                                         sizeBytes: size, modified: nil, isSuggested: false)

        let result = LargeFileScanner.trash([item])
        if result.failures.isEmpty {
            #expect(!fm.fileExists(atPath: url.path))       // gone from its original path
            #expect(result.freedBytes == size)              // credited the measured bytes
        } else {
            #expect(result.freedBytes == 0)                 // nothing credited on failure
            #expect(result.failures.first?.url == url)
            try? fm.removeItem(at: url)
        }
    }
}
