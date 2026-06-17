import Foundation
import Darwin

/// `mach_host_self()` allocates a new send right on every call and we never
/// deallocate them — sampled once a second, that leaks kernel port references
/// for the lifetime of the process. Acquire the port once instead.
private let machHost: host_t = mach_host_self()

/// Reads an integer `sysctlbyname` value (e.g. `hw.perflevel0.logicalcpu`),
/// sized from the kernel so it's correct whether the value is 32- or 64-bit.
/// nil when the name is absent (e.g. Intel has no `hw.perflevel*`).
func sysctlInt(_ name: String) -> Int? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
    if size == MemoryLayout<Int32>.size {
        var value: Int32 = 0
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    } else if size == MemoryLayout<Int64>.size {
        var value: Int64 = 0
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
    return nil
}

/// CPU utilisation split by core cluster. `overall` is always present; the
/// per-cluster figures are nil when the Performance/Efficiency layout can't be
/// trusted (Intel, or the perflevel core counts don't reconcile with the array
/// we sampled) — then the UI shows the honest blended number, never a
/// fabricated split.
struct CPUUsage {
    let overall: Double
    let performance: Double?
    let efficiency: Double?
}

/// Overall + per-cluster CPU utilisation, from the delta of per-core tick
/// counters between consecutive samples.
final class CPUUsageSampler {
    private var previousTicks: [[UInt32]] = []

    /// Apple Silicon orders `host_processor_info` as **[E-cores][P-cores]**: the
    /// first `hw.perflevel1.logicalcpu` indices are Efficiency cores, the last
    /// `hw.perflevel0.logicalcpu` are Performance (verified on hardware — a
    /// default-QoS load saturates exactly the trailing indices). Resolved once;
    /// nil unless there's a clean two-level split.
    static let clusters: (performance: Range<Int>, efficiency: Range<Int>)? = {
        guard sysctlInt("hw.nperflevels") == 2,
              let performance = sysctlInt("hw.perflevel0.logicalcpu"), performance > 0,
              let efficiency = sysctlInt("hw.perflevel1.logicalcpu"), efficiency > 0
        else { return nil }
        return (performance: efficiency..<(efficiency + performance), efficiency: 0..<efficiency)
    }()

    /// Returns CPU usage (overall + clusters), or nil on the first call / error.
    func sample() -> CPUUsage? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(machHost, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        // Trust the allocated element count (`infoCount`), not `coreCount`:
        // a buggy hypervisor can report a core count larger than the array it
        // actually returned, and indexing past it would read out of bounds.
        let safeCores = min(Int(coreCount), Int(infoCount) / Int(CPU_STATE_MAX))
        guard safeCores > 0 else { return nil }
        let ticks = (0..<safeCores).map { core -> [UInt32] in
            let base = core * Int(CPU_STATE_MAX)
            return (0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[base + $0]) }
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return nil }
        return Self.clusterUsage(ticks: ticks, previous: previousTicks, clusters: Self.clusters)
    }

    /// Pure: per-core tick arrays → overall + per-cluster busy %. The split is
    /// only filled when the cluster ranges partition `[0, core count)` exactly
    /// (contiguous, no gaps/overflow) — otherwise just `overall`, so a bad
    /// mapping degrades to the honest blended number. For testing.
    static func clusterUsage(ticks: [[UInt32]], previous: [[UInt32]],
                             clusters: (performance: Range<Int>, efficiency: Range<Int>)?) -> CPUUsage? {
        // Self-defend the precondition the caller also checks: equal-length,
        // aligned per-core arrays. Mismatched input → nil rather than a crash.
        guard previous.count == ticks.count else { return nil }
        func usage(_ indices: Range<Int>) -> Double? {
            var busy = 0.0, total = 0.0
            for core in indices {
                for state in 0..<Int(CPU_STATE_MAX) {
                    let delta = Double(ticks[core][state] &- previous[core][state])
                    total += delta
                    if state != Int(CPU_STATE_IDLE) { busy += delta }
                }
            }
            return total > 0 ? busy / total * 100 : nil
        }
        guard let overall = usage(0..<ticks.count) else { return nil }

        var performance: Double?, efficiency: Double?
        // The ranges must exactly tile [0, count): E = [0, nE), P = [nE, count).
        if let clusters,
           clusters.efficiency.lowerBound == 0,
           clusters.efficiency.upperBound == clusters.performance.lowerBound,
           clusters.performance.upperBound == ticks.count {
            performance = usage(clusters.performance)
            efficiency = usage(clusters.efficiency)
        }
        return CPUUsage(overall: overall, performance: performance, efficiency: efficiency)
    }
}

/// The macOS memory-pressure level, straight from the kernel — the same
/// green/yellow/red signal Activity Monitor shows.
enum MemoryPressure: Int {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

/// A full memory picture matching Activity Monitor's Memory tab.
struct MemorySnapshot {
    let total: UInt64
    let used: UInt64        // "Memory Used" = app + wired + compressed
    let app: UInt64         // "App Memory"
    let wired: UInt64       // "Wired Memory"
    let compressed: UInt64  // "Compressed"
    let cached: UInt64      // "Cached Files"
    let free: UInt64
    let swapUsed: UInt64
    let swapTotal: UInt64
    let pressure: MemoryPressure

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum MemoryStats {
    static func read() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(machHost, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let external = UInt64(stats.external_page_count) * pageSize
        let internalBytes = UInt64(stats.internal_page_count) * pageSize
        let app = internalBytes - min(internalBytes, purgeable)
        let cached = external + purgeable
        let free = UInt64(stats.free_count) * pageSize
        let used = app + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = swap.xsu_used
            swapTotal = swap.xsu_total
        }

        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)
        let pressure = MemoryPressure(rawValue: Int(level)) ?? .normal

        return MemorySnapshot(
            total: total, used: used, app: app, wired: wired, compressed: compressed,
            cached: cached, free: free, swapUsed: swapUsed, swapTotal: swapTotal, pressure: pressure
        )
    }
}

enum HardwareInfo {
    static let chipName: String = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
    static let coreCount = ProcessInfo.processInfo.processorCount

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var uptimeText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: ProcessInfo.processInfo.systemUptime) ?? "—"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
