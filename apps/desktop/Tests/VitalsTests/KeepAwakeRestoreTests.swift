import Testing
import Foundation
@testable import Vitals

/// Locks what a relaunch re-arms: a saved stay comes back with its screen
/// choice, an expired one doesn't, and a settings round trip survives.
@MainActor
struct KeepAwakeRestoreTests {
    private func makeSettings() -> (AppSettings, UserDefaults) {
        let name = "vitals.test.keepawake.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return (AppSettings(defaults: suite), suite)
    }

    @Test func nothingSavedRestoresNothing() {
        let (settings, _) = makeSettings()
        #expect(RemoteModel.savedKeepAwake(settings) == nil)
    }

    @Test func untilStoppedComesBackWithTheScreenChoice() throws {
        let (settings, suite) = makeSettings()
        settings.keepAwakeActive = true
        settings.keepAwakeUntil = 0
        settings.keepAwakeDisplay = true
        let saved = try #require(RemoteModel.savedKeepAwake(AppSettings(defaults: suite)))
        #expect(saved.until == nil)
        #expect(saved.display)
    }

    @Test func timedStayRestoresOnlyBeforeItEnds() throws {
        let (settings, _) = makeSettings()
        let now = Date(timeIntervalSince1970: 1_000_000)
        settings.keepAwakeActive = true
        settings.keepAwakeUntil = now.addingTimeInterval(3600).timeIntervalSince1970
        let saved = try #require(RemoteModel.savedKeepAwake(settings, now: now))
        #expect(saved.until == now.addingTimeInterval(3600))
        #expect(RemoteModel.savedKeepAwake(settings, now: now.addingTimeInterval(3601)) == nil)
    }
}
