import Foundation

/// Per-second rate from two readings of a monotonic byte counter, shared by the
/// network and disk samplers. Returns 0 when the counter went backwards (device
/// re-created or counters reset) or no time elapsed.
enum CounterRate {
    static func perSecond(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }
}
