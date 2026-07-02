import Testing
import Foundation
@testable import Vitals

/// The storage analyzer's ranking contract: sizes are applied from the
/// caller-supplied dictionary (missing entries read as zero, never crash or
/// get dropped), sorting is stable per `StorageEntrySort`, and the result is
/// always capped to `limit` — the main actor never receives more rows than it
/// can usefully show.
struct StorageRankedTests {
    private func entry(_ name: String, isDirectory: Bool = false) -> StorageEntry {
        StorageEntry(
            url: URL(fileURLWithPath: "/fake/\(name)"),
            name: name,
            sizeBytes: 0,
            isDirectory: isDirectory
        )
    }

    @Test func sizeSortOrdersDescendingAndAppliesSizes() {
        let a = entry("a")
        let b = entry("b")
        let c = entry("c")
        let sizes: [URL: UInt64] = [a.url: 100, b.url: 500, c.url: 10]

        let ranked = StorageModel.ranked([a, b, c], sizes: sizes, limit: 10, sort: .size)

        #expect(ranked.map(\.name) == ["b", "a", "c"])
        #expect(ranked.map(\.sizeBytes) == [500, 100, 10])
    }

    @Test func sizeSortTreatsMissingSizeAsZero() {
        let known = entry("known")
        let missing = entry("missing")
        let sizes: [URL: UInt64] = [known.url: 42]

        let ranked = StorageModel.ranked([known, missing], sizes: sizes, limit: 10, sort: .size)

        #expect(ranked.map(\.name) == ["known", "missing"])
        #expect(ranked.last?.sizeBytes == 0)
    }

    @Test func sizeSortCapsToLimit() {
        let items = (0..<20).map { entry("item\($0)") }
        let sizes = Dictionary(uniqueKeysWithValues: items.map { ($0.url, UInt64($0.name.dropFirst(4)) ?? 0) })

        let ranked = StorageModel.ranked(items, sizes: sizes, limit: 5, sort: .size)

        #expect(ranked.count == 5)
        // Largest indices (19...15) sort first descending by size.
        #expect(ranked.map(\.name) == ["item19", "item18", "item17", "item16", "item15"])
    }

    @Test func nameSortUsesLocalizedStandardCompareAscending() {
        let item2 = entry("item2")
        let item10 = entry("item10")
        let item1 = entry("item1")

        let ranked = StorageModel.ranked([item10, item2, item1], sizes: [:], limit: 10, sort: .name)

        // Localized standard comparison treats embedded numbers numerically,
        // so item2 sorts before item10 (not lexicographically after "item1").
        #expect(ranked.map(\.name) == ["item1", "item2", "item10"])
    }

    @Test func nameSortCapsToLimit() {
        let items = ["item1", "item2", "item3", "item4", "item5"].map { entry($0) }

        let ranked = StorageModel.ranked(items, sizes: [:], limit: 3, sort: .name)

        #expect(ranked.count == 3)
        #expect(ranked.map(\.name) == ["item1", "item2", "item3"])
    }
}

/// `StorageAnalyzer.children` lists a folder's immediate contents for the
/// drill-down browser — it must report the right `isDirectory` flag for both
/// kinds, never follow a symlink out of the tree being measured, and honour
/// `includeHidden` (dotfiles hide by default off, shown when on).
struct StorageAnalyzerChildrenTests {
    @Test func listsFilesAndDirectoriesWithCorrectFlags() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("VitalsStorageTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent("file.txt")
        try Data("hello".utf8).write(to: file)
        let subdir = root.appendingPathComponent("subdir")
        try fm.createDirectory(at: subdir, withIntermediateDirectories: true)

        let children = StorageAnalyzer.children(of: root, includeHidden: true)
        let byName = Dictionary(uniqueKeysWithValues: children.map { ($0.name, $0) })

        #expect(byName["file.txt"]?.isDirectory == false)
        #expect(byName["subdir"]?.isDirectory == true)
    }

    @Test func skipsSymlinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("VitalsStorageTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let real = root.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: real)
        let link = root.appendingPathComponent("link.txt")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let names = Set(StorageAnalyzer.children(of: root, includeHidden: true).map(\.name))

        #expect(names.contains("real.txt"))
        #expect(!names.contains("link.txt"))
    }

    @Test func includeHiddenControlsDotfileVisibility() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("VitalsStorageTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        try Data("x".utf8).write(to: root.appendingPathComponent("visible.txt"))
        try Data("x".utf8).write(to: root.appendingPathComponent(".hidden"))

        let withoutHidden = Set(StorageAnalyzer.children(of: root, includeHidden: false).map(\.name))
        #expect(withoutHidden.contains("visible.txt"))
        #expect(!withoutHidden.contains(".hidden"))

        let withHidden = Set(StorageAnalyzer.children(of: root, includeHidden: true).map(\.name))
        #expect(withHidden.contains("visible.txt"))
        #expect(withHidden.contains(".hidden"))
    }
}
