import Foundation

/// Overall CPU utilisation from `/proc/stat`, computed as the busy fraction of
/// the jiffy delta between two samples — the same approach `top` uses.
public enum ProcStat {

    /// The cumulative tick counters needed to derive usage. `idle` folds in
    /// iowait, matching the convention that time waiting on I/O isn't "busy".
    public struct Ticks: Equatable, Sendable {
        public let total: UInt64
        public let idle: UInt64
        public init(total: UInt64, idle: UInt64) {
            self.total = total
            self.idle = idle
        }
    }

    /// Parses the aggregate `cpu ` line (the first line of `/proc/stat`).
    /// Fields: user nice system idle iowait irq softirq steal guest guest_nice.
    public static func parseAggregate(_ content: String) -> Ticks? {
        for line in content.split(separator: "\n") where line.hasPrefix("cpu ") {
            let fields = line.split(separator: " ").dropFirst().compactMap { UInt64($0) }
            guard fields.count >= 5 else { return nil }
            let total = fields.reduce(0, +)
            let idle = fields[3] + fields[4]   // idle + iowait
            return Ticks(total: total, idle: idle)
        }
        return nil
    }

    /// Busy percentage (0…100) from two samples, or nil if the counters didn't
    /// advance (no elapsed time, or a counter reset).
    public static func usage(previous: Ticks, current: Ticks) -> Double? {
        let totalDelta = current.total >= previous.total ? current.total - previous.total : 0
        let idleDelta = current.idle >= previous.idle ? current.idle - previous.idle : 0
        guard totalDelta > 0, idleDelta <= totalDelta else { return nil }
        return Double(totalDelta - idleDelta) / Double(totalDelta) * 100
    }
}

/// Stateful sampler holding the previous counters; returns nil on the first call
/// (a delta needs two points), like the macOS `CPUUsageSampler`.
public final class CPUUsageSampler {
    private var previous: ProcStat.Ticks?
    private let path: String

    public init(path: String = "/proc/stat") {
        self.path = path
    }

    public func sample() -> Double? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              let current = ProcStat.parseAggregate(content) else { return nil }
        defer { previous = current }
        guard let previous else { return nil }
        return ProcStat.usage(previous: previous, current: current)
    }
}
