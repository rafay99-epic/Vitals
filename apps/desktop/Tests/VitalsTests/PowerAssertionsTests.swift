import Testing
import Foundation
@testable import Vitals

/// Locks the sleep-assertion parser: it classifies system- vs display-sleep
/// assertions, ignores unrelated types, and drops malformed / invalid entries —
/// so the Battery hub's "keeping your Mac awake" list is trustworthy.
struct PowerAssertionsTests {
    private func raw(_ dict: [Int32: [[String: Any]]]) -> [NSNumber: [[String: Any]]] {
        var out: [NSNumber: [[String: Any]]] = [:]
        for (pid, entries) in dict { out[NSNumber(value: pid)] = entries }
        return out
    }

    @Test func classifiesSystemAndDisplaySleep() {
        let result = PowerAssertions.parse(raw([
            501: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Downloading update"]],
            502: [["AssertType": "PreventUserIdleDisplaySleep", "AssertName": "Playing a movie"]],
        ]))
        #expect(result[501]?.first?.kind == .system)
        #expect(result[501]?.first?.preventsSystemSleep == true)
        #expect(result[501]?.first?.name == "Downloading update")
        #expect(result[502]?.first?.kind == .display)
        #expect(result[502]?.first?.preventsSystemSleep == false)
    }

    @Test func recognisesAllSystemSleepTypes() {
        let result = PowerAssertions.parse(raw([
            1: [["AssertType": "PreventSystemSleep"]],
            2: [["AssertType": "NoIdleSleepAssertion"]],
        ]))
        #expect(result[1]?.first?.kind == .system)
        #expect(result[2]?.first?.kind == .system)
    }

    @Test func recognisesLegacyDisplaySleepType() {
        // The legacy `NoDisplaySleepAssertion` must classify as a display blocker,
        // not be dropped as unknown.
        let result = PowerAssertions.parse(raw([
            3: [["AssertType": "NoDisplaySleepAssertion"]],
        ]))
        #expect(result[3]?.first?.kind == .display)
        #expect(result[3]?.first?.preventsSystemSleep == false)
    }

    @Test func ignoresUnrelatedAndMalformedEntries() {
        let result = PowerAssertions.parse(raw([
            10: [["AssertType": "SomeUnrelatedAssertion"]],  // not a sleep type
            11: [["AssertName": "no type key"]],             // missing required type
            12: [],                                          // no assertions
        ]))
        #expect(result[10] == nil)
        #expect(result[11] == nil)
        #expect(result[12] == nil)
        #expect(result.isEmpty)
    }

    @Test func dropsNonPositivePIDs() {
        let result = PowerAssertions.parse(raw([
            0: [["AssertType": "PreventSystemSleep"]],
            -1: [["AssertType": "PreventSystemSleep"]],
        ]))
        #expect(result.isEmpty)
    }

    @Test func multipleAssertionsPerProcess() {
        let result = PowerAssertions.parse(raw([
            777: [
                ["AssertType": "PreventUserIdleSystemSleep"],
                ["AssertType": "PreventUserIdleDisplaySleep"],
            ],
        ]))
        #expect(result[777]?.count == 2)
        #expect(result[777]?.contains { $0.preventsSystemSleep } == true)
    }
}
