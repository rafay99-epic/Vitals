import Testing
import Foundation
@testable import Vitals

/// Locks the alert firing rules: a condition must hold for its full duration
/// before firing, then a cooldown prevents one ongoing problem from notifying
/// every tick, a broken condition resets the clock, and an unavailable reading
/// never fires.
@MainActor
struct AlertEngineTests {
    private let cooldown: TimeInterval = 600
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func rule(_ metric: AlertMetric = .cpuTemp, _ comparison: AlertComparison = .above,
                      threshold: Double = 90, sustained: Double = 2) -> AlertRule {
        var rule = AlertRule(metric: metric)
        rule.comparison = comparison
        rule.threshold = threshold
        rule.sustainedMinutes = sustained
        return rule
    }

    @Test func doesNotFireUntilSustained() {
        let r = rule(sustained: 2)
        var (state, fire) = AlertEngine.step(rule: r, value: 95, state: .init(), now: t0, cooldown: cooldown)
        #expect(!fire)  // just crossed
        (state, fire) = AlertEngine.step(rule: r, value: 95, state: state, now: t0.addingTimeInterval(60), cooldown: cooldown)
        #expect(!fire)  // 1 min < 2 min
        (_, fire) = AlertEngine.step(rule: r, value: 95, state: state, now: t0.addingTimeInterval(121), cooldown: cooldown)
        #expect(fire)   // held > 2 min
    }

    @Test func cooldownBlocksRepeatThenAllows() {
        let r = rule(sustained: 0)  // fires the instant it's true
        var (state, fire) = AlertEngine.step(rule: r, value: 95, state: .init(), now: t0, cooldown: cooldown)
        #expect(fire)
        (state, fire) = AlertEngine.step(rule: r, value: 95, state: state, now: t0.addingTimeInterval(60), cooldown: cooldown)
        #expect(!fire)  // within cooldown
        (_, fire) = AlertEngine.step(rule: r, value: 95, state: state, now: t0.addingTimeInterval(601), cooldown: cooldown)
        #expect(fire)   // cooldown elapsed
    }

    @Test func brokenConditionResetsSustainClock() {
        let r = rule(sustained: 2)
        var (state, _) = AlertEngine.step(rule: r, value: 95, state: .init(), now: t0, cooldown: cooldown)
        #expect(state.trueSince != nil)
        (state, _) = AlertEngine.step(rule: r, value: 50, state: state, now: t0.addingTimeInterval(30), cooldown: cooldown)
        #expect(state.trueSince == nil)
    }

    @Test func belowComparison() {
        let r = rule(.diskFree, .below, threshold: 10, sustained: 0)
        #expect(AlertEngine.step(rule: r, value: 5, state: .init(), now: t0, cooldown: cooldown).fire)
        #expect(!AlertEngine.step(rule: r, value: 50, state: .init(), now: t0, cooldown: cooldown).fire)
    }

    @Test func unavailableReadingNeverFires() {
        let r = rule(sustained: 0)
        let (state, fire) = AlertEngine.step(
            rule: r, value: nil, state: .init(trueSince: t0), now: t0, cooldown: cooldown)
        #expect(!fire)
        #expect(state.trueSince == nil)
    }

    // MARK: Network + battery-health metrics

    @Test func readingsDispatchNewMetrics() {
        // Throughput is carried in bytes/s and reported to the engine in MB/s.
        let readings = AlertReadings(
            downloadBytesPerSec: 6_000_000,  // 6 MB/s
            uploadBytesPerSec: 2_500_000,    // 2.5 MB/s
            batteryHealthPercent: 82)
        #expect(readings.value(for: .networkDown) == 6)
        #expect(readings.value(for: .networkUp) == 2.5)
        #expect(readings.value(for: .batteryHealth) == 82)
    }

    @Test func downloadRuleComparesInMegabytes() {
        // A 5 MB/s "above" rule: fires at a 6 MB/s reading, not at 4 MB/s.
        let r = rule(.networkDown, .above, threshold: 5, sustained: 0)
        let hot = AlertReadings(downloadBytesPerSec: 6_000_000)
        let calm = AlertReadings(downloadBytesPerSec: 4_000_000)
        #expect(AlertEngine.step(rule: r, value: hot.value(for: .networkDown), state: .init(), now: t0, cooldown: cooldown).fire)
        #expect(!AlertEngine.step(rule: r, value: calm.value(for: .networkDown), state: .init(), now: t0, cooldown: cooldown).fire)
    }

    @Test func batteryHealthDefaultsToBelow() {
        #expect(AlertMetric.batteryHealth.defaultComparison == .below)
        // A "below 80%" default rule fires at 75% health, not at 90%.
        var r = AlertRule(metric: .batteryHealth)
        r.sustainedMinutes = 0
        #expect(r.threshold == 80)
        #expect(AlertEngine.step(rule: r, value: 75, state: .init(), now: t0, cooldown: cooldown).fire)
        #expect(!AlertEngine.step(rule: r, value: 90, state: .init(), now: t0, cooldown: cooldown).fire)
    }

    @Test func newMetricUnits() {
        #expect(AlertMetric.networkDown.unit == "MB/s")
        #expect(AlertMetric.networkUp.unit == "MB/s")
        #expect(AlertMetric.batteryHealth.unit == "%")
    }
}
