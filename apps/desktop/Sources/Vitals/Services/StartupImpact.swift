import Foundation
import Darwin

/// The **live resource cost** of a login item — the real memory footprint and
/// cumulative CPU time of the process it launched, read right now. Like every
/// Service it is UI-free.
///
/// Deliberately *not* a "boot time". macOS can't measure how long an individual
/// login item took at startup without instrumenting boot itself, so inventing a
/// millisecond figure would violate honesty-over-decoration. Instead this shows
/// what each item is actually costing while it runs — a real footprint and real
/// CPU seconds, or an honest "Not running" / "Running" when there's no number to
/// show.
///
/// Attribution is exact: a login item is tied to its process by the launchd
/// label→pid map (`LaunchItemScanner.runningPIDs`), never by guessing from the
/// program path (which would over-match interpreters like `/bin/sh`).
enum StartupImpact {
    /// What a login item is costing right now.
    struct Cost: Equatable {
        /// Physical memory footprint — the same figure Activity Monitor shows
        /// under "Memory".
        var memoryBytes: UInt64
        /// CPU time consumed since the process launched (cumulative, seconds).
        var cpuSeconds: Double
    }

    /// The measurable state of one login item.
    enum State: Equatable {
        /// Launched, and its cost was readable (a process we own).
        case running(Cost)
        /// Launched, but a process we can't inspect (another user / root) — we
        /// know it's running, but show no fabricated numbers.
        case runningUnreadable
        /// Not currently running.
        case idle
        /// Outside the domain we can authoritatively check (system agents/daemons):
        /// the user-domain `launchctl list` doesn't cover them, so we don't guess
        /// "idle" — we simply don't claim a state.
        case notMeasured
    }

    /// A coarse impact tier for the badge.
    enum Level { case high, medium, low, idle, unknown }

    /// Impact tier from a measured state. Footprint dominates — that's the
    /// standing cost of keeping the item resident at login. Thresholds are
    /// deliberate and documented; pure, for testing.
    static func level(_ state: State) -> Level {
        switch state {
        case .idle: return .idle
        case .runningUnreadable, .notMeasured: return .unknown
        case .running(let cost):
            let mb = Double(cost.memoryBytes) / 1_048_576
            if mb >= 500 { return .high }
            if mb >= 100 { return .medium }
            return .low
        }
    }

    /// Mach absolute-time units → nanoseconds. `ri_user_time`/`ri_system_time`
    /// are recorded in mach time units (like `mach_absolute_time`), NOT
    /// nanoseconds — on Apple Silicon the timebase is 125/3 (~41.67 ns/unit), so
    /// treating them as nanoseconds under-reports CPU by ~42×.
    private static let nanosPerMachUnit: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    /// Reads a pid's live footprint + cumulative CPU seconds via `proc_pid_rusage`
    /// (the same call `ProcessInventory` uses). Returns nil when the process is
    /// gone or we lack permission to inspect it (another user / root) — the caller
    /// then reports "running" without fabricating numbers.
    static func readCost(pid: Int32) -> Cost? {
        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard ok == 0 else { return nil }
        let machUnits = usage.ri_user_time + usage.ri_system_time
        let cpuSeconds = Double(machUnits) * Self.nanosPerMachUnit / 1_000_000_000
        return Cost(memoryBytes: usage.ri_phys_footprint, cpuSeconds: cpuSeconds)
    }

    /// The state of one launch item given the live label→pid map. Only user agents
    /// are judged running/idle — `launchctl list` in the user's gui domain is
    /// authoritative for them and their cost is readable; system agents/daemons
    /// are `notMeasured` rather than guessed.
    static func state(for item: LaunchItem, runningPIDs: [String: Int32]) -> State {
        guard item.kind == .userAgent else { return .notMeasured }
        guard let pid = runningPIDs[item.label] else { return .idle }
        if let cost = readCost(pid: pid) { return .running(cost) }
        return .runningUnreadable
    }
}
