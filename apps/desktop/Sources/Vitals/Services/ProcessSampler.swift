import Foundation
import Darwin
import PrivateSensors

/// Per-process CPU usage from `proc_pid_rusage` deltas between samples. Same
/// scale as Activity Monitor: 100% is one core, so multi-threaded work exceeds it.
final class ProcessSampler {
    struct Process: Identifiable {
        let id: pid_t
        let name: String
        let cpuPercent: Double
        /// `ri_phys_footprint`, Activity Monitor's Memory column.
        let memory: UInt64
    }

    /// Two views of one sweep. `byCPU` needs a prior sample; `byMemory` is
    /// instantaneous, so it's filled on the first tick too.
    struct Sampled {
        let byCPU: [Process]
        let byMemory: [Process]

        static let empty = Sampled(byCPU: [], byMemory: [])
    }

    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousSampleAt: UInt64 = 0

    private static let nanosPerMachTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    func sample(top count: Int) -> Sampled {
        let now = mach_absolute_time()
        let pidCount = proc_listallpids(nil, 0)
        // Cap the kernel-supplied count so a garbage value can't allocate an
        // unbounded array or overflow the Int32 byte size below.
        guard pidCount > 0, pidCount < 100_000 else { return .empty }
        let capacity = Int(pidCount) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteSize = capacity * MemoryLayout<pid_t>.size
        guard byteSize <= Int(Int32.max) else { return .empty }
        let filled = proc_listallpids(&pids, Int32(byteSize))
        guard filled > 0 else { return .empty }

        var currentCPUTime: [pid_t: UInt64] = [:]
        var currentMemory: [pid_t: UInt64] = [:]
        var deltas: [(pid: pid_t, ticks: UInt64)] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }
            currentMemory[pid] = usage.ri_phys_footprint
            // On Apple Silicon these are Mach ticks, not nanoseconds; converted below.
            let cpuTime = usage.ri_user_time + usage.ri_system_time
            currentCPUTime[pid] = cpuTime
            if let before = previousCPUTime[pid], cpuTime >= before {
                deltas.append((pid, cpuTime - before))
            }
        }

        let hadPreviousSample = previousSampleAt > 0 && now > previousSampleAt
        let wallNanos = Double(now - previousSampleAt) * Self.nanosPerMachTick
        previousCPUTime = currentCPUTime
        previousSampleAt = now

        var percentByPid: [pid_t: Double] = [:]
        if hadPreviousSample, wallNanos > 0 {
            for entry in deltas {
                let percent = Double(entry.ticks) * Self.nanosPerMachTick / wallNanos * 100
                if percent >= 0.1 { percentByPid[entry.pid] = percent }
            }
        }

        // A pid can rank in both lists; resolve its name (a syscall) once.
        var nameByPid: [pid_t: String] = [:]
        func name(_ pid: pid_t) -> String {
            if let cached = nameByPid[pid] { return cached }
            let resolved = Self.name(of: pid)
            nameByPid[pid] = resolved
            return resolved
        }

        let byCPU = percentByPid
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { Process(id: $0.key, name: name($0.key),
                           cpuPercent: $0.value, memory: currentMemory[$0.key] ?? 0) }

        let byMemory = currentMemory
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { Process(id: $0.key, name: name($0.key),
                           cpuPercent: percentByPid[$0.key] ?? 0, memory: $0.value) }

        return Sampled(byCPU: Array(byCPU), byMemory: Array(byMemory))
    }

    private static func name(of pid: pid_t) -> String {
        // Prefer the executable name over proc_name's truncated 16-char p_comm.
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let components = String(cString: pathBuffer).split(separator: "/")
            if let executable = components.last, !executable.isEmpty {
                // Some executables are named after their version ("2.1.175");
                // use the enclosing .app name instead.
                let isVersionLike = executable.allSatisfy { $0.isNumber || $0 == "." }
                if isVersionLike, let bundle = components.last(where: { $0.hasSuffix(".app") }) {
                    return String(bundle.dropLast(4))
                }
                return String(executable)
            }
        }
        var nameBuffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { return "pid \(pid)" }
        return String(cString: nameBuffer)
    }
}
