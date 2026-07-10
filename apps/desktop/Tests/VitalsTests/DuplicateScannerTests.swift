import Testing
import Foundation
@testable import Vitals

/// The Duplicates finder groups files that are **byte-for-byte identical** and
/// only ever deletes to the Trash. These tests lock the honesty guarantee (same
/// size but different content is never grouped), the shared walk's safety
/// (symlinks, hidden files, packages, size floor), the ranking, the keeper choice,
/// and the recoverable-deletion contract.
struct DuplicateScannerTests {
    // MARK: Fixtures

    private final class TempHome {
        let url: URL
        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitals-dup-\(UUID().uuidString)", isDirectory: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    @discardableResult
    private func write(_ home: URL, _ relative: String, bytes: [UInt8], ageDays: Int? = nil) throws -> URL {
        let fm = FileManager.default
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
        if let ageDays {
            let date = Date().addingTimeInterval(-Double(ageDays) * 86_400)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    /// A deterministic byte pattern — the same seed and length produce identical
    /// content; a different seed of the same length is same-size-different-content.
    private func pattern(_ seed: UInt8, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8((Int(seed) &+ $0) & 0xFF) }
    }

    private func docs(_ home: URL) -> [URL] { [home.appendingPathComponent("Documents")] }
    /// A 1-byte floor so tiny fixtures still qualify.
    private let anySize: UInt64 = 1

    // MARK: The honesty guarantee

    @Test func identicalFilesGroupedSameSizeDifferentContentIsNot() throws {
        let home = TempHome()
        let content = pattern(1, 4096)
        try write(home.url, "Documents/a.bin", bytes: content)
        try write(home.url, "Documents/copy/b.bin", bytes: content)      // identical to a.bin
        try write(home.url, "Documents/c.bin", bytes: pattern(2, 4096))  // SAME size, different bytes

        let groups = DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: anySize)
        #expect(groups.count == 1)
        #expect(Set(groups[0].files.map(\.name)) == ["a.bin", "b.bin"])
        #expect(groups[0].count == 2)  // c.bin is never lumped in despite matching size
    }

    @Test func uniqueFilesYieldNoGroups() throws {
        let home = TempHome()
        try write(home.url, "Documents/a.bin", bytes: pattern(1, 2048))
        try write(home.url, "Documents/b.bin", bytes: pattern(2, 4096))
        #expect(DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: anySize).isEmpty)
    }

    @Test func fullHashDistinguishesContent() throws {
        let home = TempHome()
        let a = try write(home.url, "Documents/a.bin", bytes: pattern(10, 4096))
        let b = try write(home.url, "Documents/b.bin", bytes: pattern(10, 4096))
        let c = try write(home.url, "Documents/c.bin", bytes: pattern(11, 4096))
        #expect(DuplicateScanner.fullHash(of: a) == DuplicateScanner.fullHash(of: b))
        #expect(DuplicateScanner.fullHash(of: a) != DuplicateScanner.fullHash(of: c))
        #expect(DuplicateScanner.fullHash(of: a) != nil)
    }

    // MARK: Walk safety (shared with LargeFileScanner via FileWalk)

    @Test func belowMinSizeIgnored() throws {
        let home = TempHome()
        let content = pattern(3, 1000)
        try write(home.url, "Documents/a.bin", bytes: content)
        try write(home.url, "Documents/b.bin", bytes: content)
        // Identical, but under a 1 MB floor → not considered.
        #expect(DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: 1024 * 1024).isEmpty)
    }

    @Test func symlinkedCopyIsNotADuplicate() throws {
        let home = TempHome()
        let real = try write(home.url, "Documents/real.bin", bytes: pattern(4, 4096))
        let link = home.url.appendingPathComponent("Documents/link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        // The symlink must never be counted as a second copy of the real file.
        #expect(DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: anySize).isEmpty)
    }

    @Test func hiddenFilesSkipped() throws {
        let home = TempHome()
        let content = pattern(5, 4096)
        try write(home.url, "Documents/.hidden.bin", bytes: content)
        try write(home.url, "Documents/visible.bin", bytes: content)
        // Only the visible copy is seen → no pair → no group.
        #expect(DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: anySize).isEmpty)
    }

    @Test func packagesAreNotHashed() throws {
        let home = TempHome()
        let content = pattern(6, 4096)
        // Identical files buried inside .app packages must not surface — packages
        // are yielded whole and never descended into or hashed.
        try write(home.url, "Documents/One.app/Contents/x.bin", bytes: content)
        try write(home.url, "Documents/Two.app/Contents/x.bin", bytes: content)
        #expect(DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: anySize).isEmpty)
    }

    // MARK: Ranking & keeper

    @Test func groupsRankedByReclaimableBytesDescending() throws {
        let home = TempHome()
        // Set A: 3 copies of 8 KB → reclaim 16 KB. Set B: 2 copies of 20 KB → reclaim 20 KB.
        let a = pattern(7, 8192)
        try write(home.url, "Documents/a1.bin", bytes: a)
        try write(home.url, "Documents/a2.bin", bytes: a)
        try write(home.url, "Documents/a3.bin", bytes: a)
        let b = pattern(8, 20480)
        try write(home.url, "Documents/b1.bin", bytes: b)
        try write(home.url, "Documents/b2.bin", bytes: b)

        let groups = DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: anySize)
        #expect(groups.count == 2)
        #expect(groups.map(\.wastedBytes) == groups.map(\.wastedBytes).sorted(by: >))
        #expect(groups.first?.count == 2)  // set B reclaims more (20 KB > 16 KB) → ranked first
    }

    @Test func keeperIsOldestRedundantAreTheRest() throws {
        let home = TempHome()
        let content = pattern(9, 4096)
        try write(home.url, "Documents/new.bin", bytes: content, ageDays: 1)
        try write(home.url, "Documents/old.bin", bytes: content, ageDays: 100)
        let groups = DuplicateScanner.scan(roots: docs(home.url), minSizeBytes: anySize)
        #expect(groups.count == 1)
        #expect(groups[0].keeper?.name == "old.bin")             // oldest kept
        #expect(groups[0].redundant.map(\.name) == ["new.bin"])  // newer is redundant
    }

    @Test func wastedBytesIsSizeTimesCountMinusOne() {
        func f(_ n: String) -> DuplicateScanner.File {
            .init(url: URL(fileURLWithPath: "/tmp/\(n)"), name: n, sizeBytes: 100, modified: nil)
        }
        let g = DuplicateScanner.Group(id: "h", sizeBytes: 100, files: [f("a"), f("b"), f("c")])
        #expect(g.wastedBytes == 200)   // keep one of three
        #expect(g.redundant.count == 2)
        #expect(g.keeper?.name == "a")
    }

    // MARK: Trash-only deletion

    @Test func trashRemovesSelectedAndCreditsBytes() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("vitals-duptrash-\(UUID().uuidString).bin")
        try Data(count: 500_000).write(to: url)
        let size = UInt64((try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        let file = DuplicateScanner.File(url: url, name: url.lastPathComponent, sizeBytes: size, modified: nil)

        let result = DuplicateScanner.trash([file])
        if result.failures.isEmpty {
            #expect(!fm.fileExists(atPath: url.path))   // gone from its original path
            #expect(result.freedBytes == size)          // credited the measured bytes
        } else {
            #expect(result.freedBytes == 0)             // nothing credited on failure
            #expect(result.failures.first?.url == url)
            try? fm.removeItem(at: url)
        }
    }
}
