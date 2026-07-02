import Testing
import Foundation
@testable import Vitals

/// Locks the durable settings mirror: values round-trip through the JSON config
/// file, alert rules stay readable, and — the whole point — settings survive a
/// UserDefaults wipe (an update / cask upgrade clearing preferences).
@MainActor
struct ConfigStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vitals-cfg-\(UUID().uuidString).json")
    }

    private func freshSuite(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func roundTripsScalarsAndStrings() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let source = freshSuite("vitals.test.cfg.a")
        source.set(5.0, forKey: "refreshInterval")
        source.set("fahrenheit", forKey: "temperatureUnit")
        source.set(true, forKey: "liquidGlass")
        ConfigStore.save(source, keys: ["refreshInterval", "temperatureUnit", "liquidGlass"], to: url)

        let restored = freshSuite("vitals.test.cfg.b")
        let count = ConfigStore.restore(into: restored, from: url)
        #expect(count == 3)
        #expect(restored.double(forKey: "refreshInterval") == 5.0)
        #expect(restored.string(forKey: "temperatureUnit") == "fahrenheit")
        #expect(restored.bool(forKey: "liquidGlass") == true)
    }

    @Test func expandsAlertRulesAsReadableJSON() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let source = freshSuite("vitals.test.cfg.rules")
        // alertRules is stored as JSON-encoded Data; the config should show it
        // as readable nested JSON, not an opaque base64 blob.
        source.set(#"[{"name":"hot"}]"#.data(using: .utf8)!, forKey: "alertRules")
        ConfigStore.save(source, keys: ["alertRules"], to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"name\""))
        #expect(!text.contains("base64"))

        let restored = freshSuite("vitals.test.cfg.rules2")
        ConfigStore.restore(into: restored, from: url)
        #expect(restored.data(forKey: "alertRules") != nil)
    }

    @Test func restoreIsNoOpWhenFileMissing() {
        let suite = freshSuite("vitals.test.cfg.missing")
        #expect(ConfigStore.restore(into: suite, from: tempURL()) == 0)
    }

    @Test func enablesLoggingOnceForUpgradingUserThenRespectsOptOut() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }

        // An existing user from before the on-by-default change: their mirrored
        // config has logging off and no migration flag.
        let firstSuite = freshSuite("vitals.test.logmig.1")
        firstSuite.set(false, forKey: "loggingEnabled")
        ConfigStore.save(firstSuite, keys: ["loggingEnabled"], to: url)

        // Opening enables logging once (the flip), despite the stored false.
        let secondSuite = freshSuite("vitals.test.logmig.2")
        let upgraded = AppSettings(defaults: secondSuite, configURL: url)
        #expect(upgraded.loggingEnabled == true)
        ConfigStore.save(secondSuite, keys: AppSettings.persistedKeys, to: url)

        // The user then turns it back off — an explicit choice that must stick.
        upgraded.loggingEnabled = false
        ConfigStore.save(secondSuite, keys: AppSettings.persistedKeys, to: url)

        // A later launch must not re-enable it (the flip already ran once).
        let thirdSuite = freshSuite("vitals.test.logmig.3")
        let reopened = AppSettings(defaults: thirdSuite, configURL: url)
        #expect(reopened.loggingEnabled == false)
    }

    @Test func settingsSurviveADefaultsWipe() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }

        // Session 1: the user customizes, and it mirrors to the config file.
        let firstSuite = freshSuite("vitals.test.cfg.durability.1")
        let first = AppSettings(defaults: firstSuite, configURL: url)
        first.refreshInterval = 5.0
        first.tabDisplayMode = .labels  // a non-default appearance choice
        // Drain the instance's serial write queue rather than racing it with a
        // manual ConfigStore.save: `first`'s init enqueued an async mirror of the
        // *registered defaults* to this same url. A raw save can land before that
        // stale init write, which then clobbers the file back to defaults — the
        // CI-only flake that blocked the promotion gate. flushConfig serializes
        // the current state and blocks until every queued write has landed in
        // order, so the file deterministically reflects {5.0, .labels}.
        first.flushConfig()

        // An update wipes UserDefaults — modeled as a brand-new, empty suite — but
        // the config file in ~/.vitals survives and rebuilds the settings. (Two
        // distinct suites, never one shared instance: a shared store + parallel
        // removePersistentDomain was a CI-only flake.)
        let secondSuite = freshSuite("vitals.test.cfg.durability.2")
        let second = AppSettings(defaults: secondSuite, configURL: url)
        #expect(second.refreshInterval == 5.0)
        #expect(second.tabDisplayMode == .labels)  // the user's appearance choice came back
    }
}
