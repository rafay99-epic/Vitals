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

/// Older builds' root fan helper decodes this file every few seconds. If the
/// shape drifts, it can't read the "all automatic" hand-back and a fan could
/// stay pinned at a manual speed.
struct FanHelperRetirementTests {
    @Test func autoStateMatchesTheOldHelperContract() throws {
        let data = try FanHelperRetirement.autoState(for: [0, 1])
        let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rows.count == 2)
        #expect(rows.map { $0["fan"] as? Int } == [0, 1])
        #expect(rows.allSatisfy { $0["mode"] as? String == "auto" })
        #expect(rows.allSatisfy { $0["rpm"] as? Double == 0 })
    }
}
