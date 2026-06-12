import Foundation
import Darwin

/// Overall CPU utilisation, computed from the delta of per-core tick counters
/// between consecutive samples.
final class CPUUsageSampler {
    private var previousTicks: [[UInt32]] = []

    /// Returns total CPU usage in 0...100, or nil on the first call.
    func sample() -> Double? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let ticks = (0..<Int(coreCount)).map { core -> [UInt32] in
            let base = core * Int(CPU_STATE_MAX)
            return (0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[base + $0]) }
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return nil }

        var busy: Double = 0
        var total: Double = 0
        for (now, before) in zip(ticks, previousTicks) {
            for state in 0..<Int(CPU_STATE_MAX) {
                let delta = Double(now[state] &- before[state])
                total += delta
                if state != Int(CPU_STATE_IDLE) { busy += delta }
            }
        }
        guard total > 0 else { return nil }
        return busy / total * 100
    }
}

enum MemoryStats {
    /// Bytes of memory in use, the way Activity Monitor counts it
    /// (app memory + wired + compressed).
    static func usedBytes() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
        return (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
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
