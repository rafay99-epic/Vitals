import Testing
import Foundation
@testable import Vitals

/// Locks the power-aware sampling throttle: the cadence follows the power source
/// exactly, and a corrupt 0 base can never divide-by-zero.
@MainActor
struct PowerThrottleTests {
    // MARK: Pure throttle logic

    @Test func acUsesBaseInterval() {
        #expect(PowerThrottle.interval(base: 2, isOnBattery: false, isLowPowerMode: false, reduceOnBattery: true) == 2)
        #expect(PowerThrottle.interval(base: 1, isOnBattery: false, isLowPowerMode: false, reduceOnBattery: true) == 1)
        #expect(PowerThrottle.interval(base: 5, isOnBattery: false, isLowPowerMode: false, reduceOnBattery: true) == 5)
    }

    @Test func batteryDoublesCappedAtFive() {
        #expect(PowerThrottle.interval(base: 1, isOnBattery: true, isLowPowerMode: false, reduceOnBattery: true) == 2)
        #expect(PowerThrottle.interval(base: 2, isOnBattery: true, isLowPowerMode: false, reduceOnBattery: true) == 4)
        // 5 s already at the ceiling — doubling would lag the menu bar, so it's held.
        #expect(PowerThrottle.interval(base: 5, isOnBattery: true, isLowPowerMode: false, reduceOnBattery: true) == 5)
    }

    @Test func batteryRespectsReduceToggle() {
        // Opting out restores the full AC cadence even on battery.
        #expect(PowerThrottle.interval(base: 1, isOnBattery: true, isLowPowerMode: false, reduceOnBattery: false) == 1)
        #expect(PowerThrottle.interval(base: 2, isOnBattery: true, isLowPowerMode: false, reduceOnBattery: false) == 2)
    }

    @Test func lowPowerFloorsAtTenRegardlessOfSource() {
        // Low Power Mode can be on while on AC — the floor applies either way,
        // and overrides the battery doubling.
        #expect(PowerThrottle.interval(base: 1, isOnBattery: true, isLowPowerMode: true, reduceOnBattery: true) == 10)
        #expect(PowerThrottle.interval(base: 2, isOnBattery: false, isLowPowerMode: true, reduceOnBattery: false) == 10)
        #expect(PowerThrottle.interval(base: 5, isOnBattery: false, isLowPowerMode: true, reduceOnBattery: true) == 10)
    }

    @Test func neverBelowHalfSecond() {
        // A corrupt 0 base must still floor at 0.5 — the Picker only offers 1/2/5
        // but a hand-edited UserDefaults 0 can't be allowed to divide-by-zero in
        // maxHistory or build a zero-second timer.
        #expect(PowerThrottle.interval(base: 0, isOnBattery: false, isLowPowerMode: false, reduceOnBattery: false) == 0.5)
        #expect(PowerThrottle.interval(base: 0, isOnBattery: true, isLowPowerMode: false, reduceOnBattery: true) == 0.5)
    }

    // MARK: AppSettings wiring

    // A unique suite per test so parallel tests never share a UserDefaults store.
    private func freshSettings(_ id: String = #function) -> AppSettings {
        let name = "vitals.test.power.\(id)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppSettings(defaults: suite)
    }

    @Test func reduceOnBatteryShipsOnByDefault() {
        let settings = freshSettings()
        #expect(settings.reduceOnBattery == true)
    }

    @Test func effectiveIntervalFollowsPowerState() {
        let settings = freshSettings()
        settings.refreshInterval = 2
        settings._setPowerStateForTesting(isOnBattery: false, isLowPowerMode: false)
        #expect(settings.effectiveRefreshInterval == 2)
        settings._setPowerStateForTesting(isOnBattery: true, isLowPowerMode: false)
        #expect(settings.effectiveRefreshInterval == 4)
        // Low Power Mode overrides the battery rule.
        settings._setPowerStateForTesting(isOnBattery: true, isLowPowerMode: true)
        #expect(settings.effectiveRefreshInterval == 10)
        settings._setPowerStateForTesting(isOnBattery: false, isLowPowerMode: true)
        #expect(settings.effectiveRefreshInterval == 10)
        // Back to AC, normal mode — the user's pick returns.
        settings._setPowerStateForTesting(isOnBattery: false, isLowPowerMode: false)
        #expect(settings.effectiveRefreshInterval == 2)
    }

    @Test func reduceOnBatteryOptOutRestoresFullRate() {
        let settings = freshSettings()
        settings.refreshInterval = 2
        settings._setPowerStateForTesting(isOnBattery: true, isLowPowerMode: false)
        settings.reduceOnBattery = false
        #expect(settings.effectiveRefreshInterval == 2)
    }
}
