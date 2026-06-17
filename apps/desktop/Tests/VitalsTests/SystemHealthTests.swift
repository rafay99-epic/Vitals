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

/// Maximum Capacity must match what macOS shows, so it's parsed from
/// `system_profiler`'s (non-localized) JSON. Lock the parse against the real
/// shape and against junk.
struct BatteryHealthTests {
    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test func parsesMaximumCapacityFromRealShape() {
        let data = json("""
        {"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_cycle_count":173,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"95%"}}]}
        """)
        #expect(BatteryHealth.parse(data) == 95)
    }

    @Test func returnsNilWhenAbsentOrOutOfRange() {
        #expect(BatteryHealth.parse(json("{\"SPPowerDataType\":[{}]}")) == nil)
        #expect(BatteryHealth.parse(json("not json")) == nil)
        // A nonsense >100% reading is rejected rather than shown.
        #expect(BatteryHealth.parse(json("""
        {"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"150%"}}]}
        """)) == nil)
    }
}

/// The power-adapter card reads the AppleSmartBattery `AdapterDetails` dict.
/// Lock the pure parser: live delivered watts = negotiated V×A, every field is
/// optional, and an absent/empty dict means "on battery" (nil) — never a
/// fabricated adapter.
struct AdapterInfoTests {
    @Test func parsesRealAdapterDict() {
        let adapter = AdapterInfo.parse(from: [
            "Watts": 96,
            "Voltage": 20_000,   // mV
            "Current": 3_000,    // mA
            "Description": "USB-C Power Adapter",
            "IsWireless": false,
        ])
        #expect(adapter?.watts == 96)
        #expect(adapter?.voltage == 20)
        #expect(adapter?.amperage == 3)
        #expect(adapter?.deliveredWatts == 60)   // 20 V × 3 A, the live PD draw
        #expect(adapter?.name == "USB-C Power Adapter")
        #expect(adapter?.isWireless == false)
    }

    @Test func nilWhenOnBattery() {
        #expect(AdapterInfo.parse(from: nil) == nil)
        #expect(AdapterInfo.parse(from: [:]) == nil)
        // macOS leaves a stub dict on battery — no power figures means no adapter.
        #expect(AdapterInfo.parse(from: ["FamilyCode": 0]) == nil)
    }

    @Test func toleratesMissingKeys() {
        // A charger reporting only its rating: rated watts present, rest nil —
        // and no V×A, so no fabricated delivered figure.
        let adapter = AdapterInfo.parse(from: ["Watts": 30])
        #expect(adapter != nil)
        #expect(adapter?.watts == 30)
        #expect(adapter?.voltage == nil)
        #expect(adapter?.deliveredWatts == nil)
        #expect(adapter?.name == nil)
        #expect(adapter?.isWireless == false)
    }

    @Test func nameFallsBackToDescriptionAndHonorsWireless() {
        let adapter = AdapterInfo.parse(from: ["Watts": 15, "Description": "magsafe", "IsWireless": true])
        #expect(adapter?.name == "magsafe")
        #expect(adapter?.isWireless == true)
    }
}
