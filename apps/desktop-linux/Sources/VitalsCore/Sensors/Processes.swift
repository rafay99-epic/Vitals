import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Top processes by CPU, from `/proc/[pid]/stat` deltas — the same model as the
/// macOS `ProcessSampler` (100% = one core fully busy).
public enum ProcPidStat {

    /// Sums `utime` + `stime` (fields 14 and 15, in clock ticks) from a
    /// `/proc/<pid>/stat` line. `comm` (field 2) is wrapped in parentheses and
    /// may itself contain spaces or `)`, so fields are counted from the LAST
    /// `)` — the robust approach the kernel docs recommend.
    public static func parseCPUTicks(_ stat: String) -> UInt64? {
        guard let close = stat.lastIndex(of: ")") else { return nil }
        let rest = stat[stat.index(after: close)...]
        let fields = rest.split(separator: " ")
        // After ')', field[0] is `state` (overall field 3); utime is field 14
        // (index 11), stime is field 15 (index 12).
        guard fields.count > 12, let utime = UInt64(fields[11]), let stime = UInt64(fields[12]) else { return nil }
        return utime + stime
    }

    /// CPU percentage from a tick delta over a wall-clock interval. Pure, so the
    /// arithmetic is unit-tested without sampling real processes.
    public static func cpuPercent(deltaTicks: UInt64, wallSeconds: Double, clockTicks: Double) -> Double {
        guard wallSeconds > 0, clockTicks > 0 else { return 0 }
        return Double(deltaTicks) / clockTicks / wallSeconds * 100
    }
}

/// Stateful sampler: remembers each pid's CPU ticks and the sample time, then
/// reports the busiest processes on the next call. Returns empty on the first
/// call (a delta needs two points).
public final class ProcessSampler {
    private var previousTicks: [Int: UInt64] = [:]
    private var previousAt: Date?
    private let procRoot: String
    private let clockTicks: Double

    public init(procRoot: String = "/proc") {
        self.procRoot = procRoot
        #if canImport(Glibc) || canImport(Darwin)
        let hz = sysconf(Int32(_SC_CLK_TCK))
        self.clockTicks = hz > 0 ? Double(hz) : 100
        #else
        self.clockTicks = 100
        #endif
    }

    public func sample(top count: Int, now: Date = Date()) -> [ProcessUsage] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: procRoot) else { return [] }

        var current: [Int: UInt64] = [:]
        var deltas: [(pid: Int, name: String, ticks: UInt64)] = []
        for entry in entries {
            guard let pid = Int(entry) else { continue }   // numeric dirs are processes
            let dir = "\(procRoot)/\(entry)"
            guard let stat = try? String(contentsOfFile: "\(dir)/stat", encoding: .utf8),
                  let ticks = ProcPidStat.parseCPUTicks(stat) else { continue }
            current[pid] = ticks
            if let before = previousTicks[pid], ticks >= before, ticks - before > 0 {
                let name = (try? String(contentsOfFile: "\(dir)/comm", encoding: .utf8))?.trimmed ?? "pid \(pid)"
                deltas.append((pid, name, ticks - before))
            }
        }

        let wall = previousAt.map { now.timeIntervalSince($0) } ?? 0
        defer { previousTicks = current; previousAt = now }
        guard wall > 0 else { return [] }

        return deltas
            .sorted { $0.ticks > $1.ticks }
            .prefix(count)
            .compactMap { entry in
                let percent = ProcPidStat.cpuPercent(deltaTicks: entry.ticks, wallSeconds: wall, clockTicks: clockTicks)
                guard percent >= 0.1 else { return nil }
                return ProcessUsage(pid: entry.pid, name: entry.name, cpuPercent: percent)
            }
    }
}
