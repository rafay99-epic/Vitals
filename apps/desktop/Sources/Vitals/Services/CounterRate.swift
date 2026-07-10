import Foundation

/// Per-second rate from two readings of a monotonic byte counter — the one
/// delta rule every throughput sampler (network interfaces, block-storage
/// drivers) shares, extracted so the guard semantics can't drift between
/// them. Returns 0 rather than a negative or absurd value when the counter
/// went **backwards** (the device was re-created / its counters reset) or
/// when no time elapsed — honesty over a fabricated spike. Pure and
/// unit-testable.
enum CounterRate {
    static func perSecond(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }
}
