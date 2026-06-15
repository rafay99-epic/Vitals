import Testing
import Foundation
@testable import Vitals

/// The Health verdict is a pure function of real readings — these lock the
/// band thresholds and the "worst signal wins" rule so the tab can never quietly
/// drift into flattering (or alarmist) territory.
struct SystemHealthTests {
    @Test func thermalStateMapsToBands() {
        #expect(SystemHealth.thermalLevel(.nominal) == .good)
        #expect(SystemHealth.thermalLevel(.fair) == .elevated)
        #expect(SystemHealth.thermalLevel(.serious) == .high)
        #expect(SystemHealth.thermalLevel(.critical) == .critical)
    }

    @Test func memoryPressureMapsToBands() {
        #expect(SystemHealth.pressureLevel(.normal) == .good)
        #expect(SystemHealth.pressureLevel(.warning) == .elevated)
        #expect(SystemHealth.pressureLevel(.critical) == .critical)
    }

    @Test func temperatureBandsAreMonotonic() {
        #expect(SystemHealth.temperatureLevel(celsius: 55) == .good)
        #expect(SystemHealth.temperatureLevel(celsius: 80) == .elevated)
        #expect(SystemHealth.temperatureLevel(celsius: 90) == .high)
        #expect(SystemHealth.temperatureLevel(celsius: 99) == .critical)
    }

    @Test func fanNeverReadsWorseThanElevated() {
        // A maxed fan is cooling working hard, not a failure.
        #expect(SystemHealth.fanLevel(rpm: 6000, maxRPM: 6000) == .elevated)
        #expect(SystemHealth.fanLevel(rpm: 1200, maxRPM: 6000) == .good)
        // A fanless Mac (no rated ceiling) is never penalised.
        #expect(SystemHealth.fanLevel(rpm: 0, maxRPM: 0) == .good)
    }

    @Test func throttlingTracksSeriousAndAbove() {
        #expect(!SystemHealth.isThrottling(.nominal))
        #expect(!SystemHealth.isThrottling(.fair))
        #expect(SystemHealth.isThrottling(.serious))
        #expect(SystemHealth.isThrottling(.critical))
    }

    @Test func worstSignalWins() {
        let levels: [SystemHealth.Level] = [.good, .critical, .elevated]
        #expect(levels.max() == .critical)
    }

    @Test func headlineCallsOutThrottling() {
        #expect(SystemHealth.headline(level: .good, throttling: false) == "Running smoothly")
        #expect(SystemHealth.headline(level: .high, throttling: true) == "Throttling to cool down")
        #expect(SystemHealth.headline(level: .critical, throttling: true) == "Throttling under heavy load")
    }
}

/// Battery condition comes from the pack's own fault flag, not an invented
/// capacity cutoff — lock that so a healthy battery never reads "Service
/// Recommended" and a flagged one never reads "Normal".
struct BatteryConditionTests {
    @Test func normalWhenNoPermanentFault() {
        #expect(BatterySnapshot.condition(permanentFailureStatus: 0) == "Normal")
        #expect(BatterySnapshot.condition(permanentFailureStatus: nil) == "Normal")
    }

    @Test func serviceRecommendedWhenFaultFlagged() {
        #expect(BatterySnapshot.condition(permanentFailureStatus: 1) == "Service Recommended")
        #expect(BatterySnapshot.condition(permanentFailureStatus: 64) == "Service Recommended")
    }
}
