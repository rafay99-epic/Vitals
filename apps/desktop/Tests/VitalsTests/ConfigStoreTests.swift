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
        source.set("dashboard,gpu,storage", forKey: "tabOrder")
        source.set(true, forKey: "liquidGlass")
        ConfigStore.save(source, keys: ["refreshInterval", "tabOrder", "liquidGlass"], to: url)

        let restored = freshSuite("vitals.test.cfg.b")
        let count = ConfigStore.restore(into: restored, from: url)
        #expect(count == 3)
        #expect(restored.double(forKey: "refreshInterval") == 5.0)
        #expect(restored.string(forKey: "tabOrder") == "dashboard,gpu,storage")
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

    @Test func settingsSurviveADefaultsWipe() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }

        // Session 1: the user customizes, and it mirrors to the config file.
        let firstSuite = freshSuite("vitals.test.cfg.durability.1")
        let first = AppSettings(defaults: firstSuite, configURL: url)
        first.refreshInterval = 5.0
        first.hiddenTabs = []  // "show every tab"
        ConfigStore.save(firstSuite, keys: AppSettings.persistedKeys, to: url)

        // An update wipes UserDefaults — modeled as a brand-new, empty suite — but
        // the config file in ~/.vitals survives and rebuilds the settings. (Two
        // distinct suites, never one shared instance: a shared store + parallel
        // removePersistentDomain was a CI-only flake.)
        let secondSuite = freshSuite("vitals.test.cfg.durability.2")
        let second = AppSettings(defaults: secondSuite, configURL: url)
        #expect(second.refreshInterval == 5.0)
        #expect(second.hiddenTabs.isEmpty)  // the user's "all tabs" choice came back
    }
}
