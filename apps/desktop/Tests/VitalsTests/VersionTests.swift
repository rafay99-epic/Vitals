import Testing
import Foundation
@testable import Vitals

/// `Updater.isVersion(_:newerThan:)` decides whether the auto-updater
/// offers a release — a wrong answer here means missed updates or an
/// update loop.
struct VersionTests {
    @Test func newerMinorIsNewer() {
        #expect(Updater.isVersion("0.11", newerThan: "0.10"))
    }

    @Test func equalIsNotNewer() {
        #expect(!Updater.isVersion("0.10", newerThan: "0.10"))
    }

    @Test func olderIsNotNewer() {
        #expect(!Updater.isVersion("0.9", newerThan: "0.10"))
    }

    @Test func comparesNumericallyNotLexicographically() {
        // "0.10" > "0.9" numerically, but "0.10" < "0.9" as strings.
        #expect(Updater.isVersion("0.10", newerThan: "0.9"))
    }

    @Test func missingComponentsCountAsZero() {
        #expect(Updater.isVersion("1.0.1", newerThan: "1.0"))
        #expect(!Updater.isVersion("1.0", newerThan: "1.0.0"))
    }

    @Test func nonNumericSuffixesAreIgnored() {
        #expect(Updater.isVersion("1.2-beta", newerThan: "1.1"))
    }
}

/// The shared state file is the contract between the GUI and the root
/// fan daemon; a coding drift would silently break fan control.
struct FanCommandTests {
    @Test func codableRoundTrip() throws {
        let commands = [
            FanCommand(fan: 0, mode: .manual, rpm: 2400),
            FanCommand(fan: 1, mode: .auto, rpm: 0),
        ]
        let data = try JSONEncoder().encode(commands)
        let decoded = try JSONDecoder().decode([FanCommand].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].fan == 0)
        #expect(decoded[0].mode == FanCommand.Mode.manual)
        #expect(decoded[0].rpm == 2400)
        #expect(decoded[1].mode == FanCommand.Mode.auto)
    }

    @Test func stateStoreCreatesMissingParentDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitals-fan-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root
            .appendingPathComponent("support", isDirectory: true)
            .appendingPathComponent("fan-state.json")
        let commands = [FanCommand(fan: 0, mode: .manual, rpm: 6550)]

        try FanControl.writeCommands(commands, to: url)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: url.deletingLastPathComponent().path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
        let decoded = FanControl.loadCommands(from: url)
        #expect(decoded.count == 1)
        #expect(decoded[0].fan == 0)
        #expect(decoded[0].mode == .manual)
        #expect(decoded[0].rpm == 6550)
    }
}
