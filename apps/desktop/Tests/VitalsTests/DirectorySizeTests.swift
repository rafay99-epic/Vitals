import Testing
import Foundation
@testable import Vitals

/// `AppInventory.directorySize` sizes app bundles and cleanup targets. Sizes are
/// allocated bytes, so assertions compare with `>=` against logical content,
/// never exact byte counts.
struct DirectorySizeTests {
    @Test func countsNestedFilesAndPlainFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitalsSizeTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("x.bin")
        try Data(repeating: 0x41, count: 2_000).write(to: file)
        try Data(repeating: 0x41, count: 500).write(to: root.appendingPathComponent("y.bin"))

        #expect(AppInventory.directorySize(root) >= 2_500)
        #expect(AppInventory.directorySize(file) >= 2_000)
        #expect(AppInventory.directorySize(root.appendingPathComponent("missing")) == 0)
    }
}
