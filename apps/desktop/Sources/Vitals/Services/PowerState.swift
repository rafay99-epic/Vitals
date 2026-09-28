import Foundation
import IOKit.ps

enum PowerState {
    /// Always false on a desktop Mac. Cheap enough to call once per tick.
    static func isOnBattery() -> Bool {
        // Copy (+1) → takeRetainedValue; Get (+0) → takeUnretainedValue.
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let raw = IOPSGetProvidingPowerSourceType(snapshot) else { return false }
        return raw.takeUnretainedValue() as String == (kIOPSBatteryPowerValue as String)
    }
}

/// Power-aware sampling cadence.
///
/// - AC: the user's chosen interval.
/// - Battery (with `reduceOnBattery`): doubled, capped at 5 s.
/// - Low Power Mode: at least 10 s, even on AC.
enum PowerThrottle {
    /// A corrupt 0 must never divide-by-zero in `maxHistory` or the timer.
    static let minimumInterval: Double = 0.5
    static let lowPowerFloor: Double = 10
    /// Slower than this on battery makes the menu-bar readout feel broken.
    static let batteryCeiling: Double = 5

    static func interval(base: Double, isOnBattery: Bool, isLowPowerMode: Bool, reduceOnBattery: Bool) -> Double {
        if isLowPowerMode { return max(base, lowPowerFloor) }
        if isOnBattery && reduceOnBattery { return min(max(base * 2, minimumInterval), batteryCeiling) }
        return max(base, minimumInterval)
    }
}
