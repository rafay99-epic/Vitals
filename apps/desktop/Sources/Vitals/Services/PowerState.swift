import Foundation
import IOKit.ps

/// Reads the Mac's current power source (AC vs. battery). Pure IOKit query — no
/// syscalls, no spawning — so it's cheap to call once per tick from
/// `VitalsModel`/`AppSettings` to keep the sampling cadence in sync with the
/// power state without installing a run-loop source.
enum PowerState {
    /// True when the Mac is running on battery (no charger attached). On a
    /// desktop Mac with no battery this is always false.
    static func isOnBattery() -> Bool {
        // `IOPSCopyPowerSourcesInfo` is a Copy (+1) → takeRetainedValue so ARC
        // owns the snapshot. `IOPSGetProvidingPowerSourceType` is a Get (+0) →
        // borrow the returned string, don't retain it.
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let raw = IOPSGetProvidingPowerSourceType(snapshot) else { return false }
        return raw.takeUnretainedValue() as String == (kIOPSBatteryPowerValue as String)
    }

    /// True while macOS' Low Power Mode is active (`ProcessInfo` reflects it the
    /// moment the user toggles it in System Settings or the OS engages it).
    static func isLowPowerMode() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

/// The power-aware sampling throttle. Pure and stateless so the cadence and
/// animation rules are unit-testable without touching IOKit or `ProcessInfo`.
///
/// - AC: the user's chosen interval, unchanged.
/// - Battery (with `reduceOnBattery`): double the interval, capped at 5 s — the
///   menu bar still feels live, but half the wakeups.
/// - Low Power Mode: floor of 10 s, matching macOS' own "slow everything down"
///   intent. Overrides the battery rule (Low Power Mode can be on while on AC).
enum PowerThrottle {
    /// Hard floor for any interval — a corrupt 0 must never divide-by-zero in
    /// `maxHistory` or the timer.
    static let minimumInterval: Double = 0.5
    /// Low Power Mode never samples faster than this.
    static let lowPowerFloor: Double = 10
    /// On battery the throttled interval never exceeds this — slower would make
    /// the menu-bar readout feel broken.
    static let batteryCeiling: Double = 5

    /// The effective sampling interval for the given power state.
    static func interval(base: Double, isOnBattery: Bool, isLowPowerMode: Bool, reduceOnBattery: Bool) -> Double {
        if isLowPowerMode { return max(base, lowPowerFloor) }
        if isOnBattery && reduceOnBattery { return min(max(base * 2, minimumInterval), batteryCeiling) }
        return max(base, minimumInterval)
    }

    /// Whether the CPU-rasterized menu-bar icon animation should pause. It's off
    /// by default already (~11% continuous CPU); for users who opt in, it stops
    /// on battery (when `reduceOnBattery` is on) or in Low Power Mode, mirroring
    /// macOS' own "reduce motion when saving power".
    static func suppressAnimation(isOnBattery: Bool, isLowPowerMode: Bool, reduceOnBattery: Bool) -> Bool {
        isLowPowerMode || (isOnBattery && reduceOnBattery)
    }
}
