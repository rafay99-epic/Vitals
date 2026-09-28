import Foundation
import Darwin

/// `mach_host_self()` allocates a new send right on every call, which leaks a
/// port reference per sample. Acquire it once.
private let machHost: host_t = mach_host_self()

/// Integer `sysctlbyname`, sized from the kernel so 32- and 64-bit values both
/// work. Nil when the name is absent (Intel has no `hw.perflevel*`).
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

/// One logical core's utilisation. `id` is the `host_processor_info` index.
struct CoreUsage: Identifiable {
    let id: Int
    let percent: Double
    let isPerformance: Bool
}

/// CPU utilisation by cluster. The P/E figures are nil when the layout can't be
/// trusted (Intel, or perflevel counts don't match the sampled array).
struct CPUUsage {
    let overall: Double
    let performance: Double?
    let efficiency: Double?
    /// Index-ordered. Empty unless there's a trusted P/E split.
    let perCore: [CoreUsage]
}

/// CPU utilisation from per-core tick deltas between consecutive samples.
final class CPUUsageSampler {
    private var previousTicks: [[UInt32]] = []

    /// Apple Silicon orders `host_processor_info` as [E-cores][P-cores]: the
    /// first `hw.perflevel1.logicalcpu` indices are Efficiency, the rest
    /// Performance (verified on hardware). Nil unless there are exactly two levels.
    static let clusters: (performance: Range<Int>, efficiency: Range<Int>)? = {
        guard sysctlInt("hw.nperflevels") == 2,
              let performance = sysctlInt("hw.perflevel0.logicalcpu"), performance > 0,
              let efficiency = sysctlInt("hw.perflevel1.logicalcpu"), efficiency > 0
        else { return nil }
        return (performance: efficiency..<(efficiency + performance), efficiency: 0..<efficiency)
    }()

    /// Nil on the first call or on error.
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

        // Trust `infoCount`, not `coreCount`: a buggy hypervisor can report more
        // cores than the array holds, and indexing past it reads out of bounds.
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

    /// The P/E split is only filled when the cluster ranges tile
    /// `[0, core count)` exactly; otherwise just `overall`.
    static func clusterUsage(ticks: [[UInt32]], previous: [[UInt32]],
                             clusters: (performance: Range<Int>, efficiency: Range<Int>)?) -> CPUUsage? {
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
        var perCore: [CoreUsage] = []
        // E = [0, nE), P = [nE, count).
        if let clusters,
           clusters.efficiency.lowerBound == 0,
           clusters.efficiency.upperBound == clusters.performance.lowerBound,
           clusters.performance.upperBound == ticks.count {
            performance = usage(clusters.performance)
            efficiency = usage(clusters.efficiency)
            perCore = (0..<ticks.count).map { index in
                CoreUsage(id: index,
                          percent: usage(index..<(index + 1)) ?? 0,
                          isPerformance: clusters.performance.contains(index))
            }
        }
        return CPUUsage(overall: overall, performance: performance, efficiency: efficiency, perCore: perCore)
    }
}

/// Kernel memory-pressure level, the same signal Activity Monitor shows.
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
    // Cumulative VM counters since boot. `VitalsModel` diffs them into `MemoryActivity`.
    let pageIns: UInt64
    let pageOuts: UInt64
    let swapIns: UInt64
    let swapOuts: UInt64
    let compressions: UInt64
    let decompressions: UInt64
}

/// VM activity in pages per second, from two `MemorySnapshot` readings.
struct MemoryActivity {
    let pageInsPerSec: Double
    let pageOutsPerSec: Double
    let swapInsPerSec: Double
    let swapOutsPerSec: Double
    let compressionsPerSec: Double
    let decompressionsPerSec: Double
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
            cached: cached, free: free, swapUsed: swapUsed, swapTotal: swapTotal, pressure: pressure,
            pageIns: UInt64(stats.pageins), pageOuts: UInt64(stats.pageouts),
            swapIns: UInt64(stats.swapins), swapOuts: UInt64(stats.swapouts),
            compressions: UInt64(stats.compressions), decompressions: UInt64(stats.decompressions)
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
        uptimeFormatter.string(from: ProcessInfo.processInfo.systemUptime) ?? "—"
    }

    private static let uptimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
