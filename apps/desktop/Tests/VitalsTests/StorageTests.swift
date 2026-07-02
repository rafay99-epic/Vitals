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

/// `AppInventory.directorySize(_:accumulating:)` — the subtree-accumulating
/// walker that measures a directory's total allocated size in one pass while
/// also collecting subtotals for arbitrary watch paths nested inside it, so a
/// scan of e.g. ~/Library can report several caches' sizes without a walk
/// each. Sizes come from `totalFileAllocatedSize` (allocated, not logical,
/// bytes), so assertions here only ever compare against *directly measured*
/// values or use `>=` against known logical content — never exact byte
/// equality against content length.
struct AppInventoryDirectorySizeTests {
    /// `FileManager.enumerator(at:)` reports canonical paths (e.g. `/private/var/...`),
    /// while `temporaryDirectory` hands back the non-canonical `/var/...` alias — so a
    /// watch path built from the un-resolved root would never prefix-match what the
    /// walker sees. Resolve through `realpath(3)` once, up front, so every URL derived
    /// from `root` agrees with the enumerator on the canonical path.
    private func makeRoot() throws -> URL {
        let raw = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitalsInventoryTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        guard let resolved = realpath(raw.path, nil) else { return raw }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try Data([UInt8](repeating: 0x41, count: bytes)).write(to: url)
    }

    @Test func watchDeepInsideRootMatchesDirectMeasurement() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // A file outside the watch, so total and subtotal can genuinely differ.
        try write(1_000, to: root.appendingPathComponent("outside.bin"))

        let watchDir = root.appendingPathComponent("deep/nested/watch", isDirectory: true)
        try FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)
        try write(2_000, to: watchDir.appendingPathComponent("inside1.bin"))
        try write(500, to: watchDir.appendingPathComponent("inside2.bin"))

        let (total, subtotals) = AppInventory.directorySize(root, accumulating: [watchDir.path])
        let direct = AppInventory.directorySize(watchDir)

        #expect(subtotals[watchDir.path] == direct)
        #expect(total >= direct)
        // Allocated bytes are never less than the logical bytes we wrote.
        #expect(direct >= 2_500)
    }

    @Test func multipleWatchesAtDifferentDepthsGetIndependentSubtotals() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let watchA = root.appendingPathComponent("a", isDirectory: true)
        try FileManager.default.createDirectory(at: watchA, withIntermediateDirectories: true)
        try write(1_000, to: watchA.appendingPathComponent("a1.bin"))

        let watchB = root.appendingPathComponent("x/y/b", isDirectory: true)
        try FileManager.default.createDirectory(at: watchB, withIntermediateDirectories: true)
        try write(3_000, to: watchB.appendingPathComponent("b1.bin"))
        try write(1_500, to: watchB.appendingPathComponent("b2.bin"))

        let (total, subtotals) = AppInventory.directorySize(root, accumulating: [watchA.path, watchB.path])
        let directA = AppInventory.directorySize(watchA)
        let directB = AppInventory.directorySize(watchB)

        #expect(subtotals[watchA.path] == directA)
        #expect(subtotals[watchB.path] == directB)
        #expect(directA >= 1_000)
        #expect(directB >= 4_500)
        #expect(total >= directA + directB)
    }

    @Test func emptyWatchComesBackPresentWithZero() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(100, to: root.appendingPathComponent("other.bin"))
        let watchDir = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)

        let (_, subtotals) = AppInventory.directorySize(root, accumulating: [watchDir.path])

        // Presence, not just value: the key exists even though nothing lives there.
        #expect(subtotals.keys.contains(watchDir.path))
        #expect(subtotals[watchDir.path] == 0)
    }

    @Test func watchEqualToRootMatchesTotal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1_000, to: root.appendingPathComponent("f1.bin"))
        let subdir = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try write(2_000, to: subdir.appendingPathComponent("f2.bin"))

        let (total, subtotals) = AppInventory.directorySize(root, accumulating: [root.path])

        #expect(subtotals[root.path] == total)
        #expect(total >= 3_000)
    }

    @Test func plainDirectorySizeMatchesAccumulatingEmptyTotal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1_234, to: root.appendingPathComponent("f1.bin"))
        let subdir = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try write(2_345, to: subdir.appendingPathComponent("f2.bin"))

        let plain = AppInventory.directorySize(root)
        let (total, _) = AppInventory.directorySize(root, accumulating: [])

        #expect(plain == total)
    }
}

/// `SizingGate` — a counting gate so however many sizing streams are open at
/// once, the number of concurrent directory walks never exceeds `width`.
/// This is a structural guarantee of `acquire`/`release`, not a timing one:
/// wherever many tasks race to acquire, the count of tasks holding the gate
/// between a completed `acquire()` and its matching `release()` can never
/// exceed `width`, regardless of how the scheduler interleaves them — so the
/// assertion below needs no sleeps or timing assumptions to be deterministic.
private actor ConcurrencyPeakCounter {
    private var current = 0
    private var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func exit() {
        current -= 1
    }

    func peakValue() -> Int { peak }
}

struct SizingGateTests {
    @Test func neverExceedsConfiguredWidth() async {
        let width = 2
        let gate = SizingGate(width: width)
        let counter = ConcurrencyPeakCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    await counter.exit()
                    await gate.release()
                }
            }
        }

        let peak = await counter.peakValue()
        #expect(peak <= width)
    }
}
