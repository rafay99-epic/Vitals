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

    @Test func networkRulesReadTheirDirection() {
        // The readings carry canonical MB/s; each network metric must map to
        // its own direction, and a pre-baseline (nil) reading can never fire.
        var readings = AlertReadings()
        readings.networkDownMBps = 250
        readings.networkUpMBps = 3
        #expect(readings.value(for: .networkDownload) == 250)
        #expect(readings.value(for: .networkUpload) == 3)

        let down = rule(.networkDownload, .above, threshold: 100, sustained: 0)
        #expect(AlertEngine.step(rule: down, value: readings.value(for: .networkDownload),
                                 state: .init(), now: t0, cooldown: cooldown).fire)
        let up = rule(.networkUpload, .above, threshold: 100, sustained: 0)
        #expect(!AlertEngine.step(rule: up, value: readings.value(for: .networkUpload),
                                  state: .init(), now: t0, cooldown: cooldown).fire)
        #expect(!AlertEngine.step(rule: down, value: AlertReadings().value(for: .networkDownload),
                                  state: .init(), now: t0, cooldown: cooldown).fire)
    }

    @Test func diskRulesReadTheirDirection() {
        // Same shape as the network test: canonical MB/s, each disk metric maps
        // to its own direction, and a pre-baseline (nil) reading can never fire.
        var readings = AlertReadings()
        readings.diskReadMBps = 800
        readings.diskWriteMBps = 30
        #expect(readings.value(for: .diskRead) == 800)
        #expect(readings.value(for: .diskWrite) == 30)

        let read = rule(.diskRead, .above, threshold: 500, sustained: 0)
        #expect(AlertEngine.step(rule: read, value: readings.value(for: .diskRead),
                                 state: .init(), now: t0, cooldown: cooldown).fire)
        let write = rule(.diskWrite, .above, threshold: 500, sustained: 0)
        #expect(!AlertEngine.step(rule: write, value: readings.value(for: .diskWrite),
                                  state: .init(), now: t0, cooldown: cooldown).fire)
        #expect(!AlertEngine.step(rule: read, value: AlertReadings().value(for: .diskRead),
                                  state: .init(), now: t0, cooldown: cooldown).fire)
    }

    @Test func unavailableReadingNeverFires() {
        let r = rule(sustained: 0)
        let (state, fire) = AlertEngine.step(
            rule: r, value: nil, state: .init(trueSince: t0), now: t0, cooldown: cooldown)
        #expect(!fire)
        #expect(state.trueSince == nil)
    }
}
