import Foundation
import Darwin
import PrivateSensors

/// Per-process CPU usage, computed from `proc_pid_rusage` deltas between
/// consecutive samples — the same data Activity Monitor shows (100% = one
/// core fully busy, so values above 100% are normal for multi-threaded work).
final class ProcessSampler {
    struct Process: Identifiable {
        let id: pid_t
        let name: String
        let cpuPercent: Double
    }

    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousSampleAt: UInt64 = 0

    private static let nanosPerMachTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    func sample(top count: Int) -> [Process] {
        let now = mach_absolute_time()
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        var currentCPUTime: [pid_t: UInt64] = [:]
        var deltas: [(pid: pid_t, ticks: UInt64)] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }
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
        guard hadPreviousSample, wallNanos > 0 else { return [] }

        return deltas
            .sorted { $0.ticks > $1.ticks }
            .prefix(count)
            .compactMap { entry in
                let percent = Double(entry.ticks) * Self.nanosPerMachTick / wallNanos * 100
                guard percent >= 0.1 else { return nil }
                return Process(id: entry.pid, name: Self.name(of: entry.pid), cpuPercent: percent)
            }
    }

    private static func name(of pid: pid_t) -> String {
        // The executable name is friendlier than proc_name's 16-char p_comm,
        // which truncates and can be an arbitrary string for helper processes.
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let components = String(cString: pathBuffer).split(separator: "/")
            if let executable = components.last, !executable.isEmpty {
                // Some executables are named after their version ("2.1.175");
                // the enclosing .app bundle is the recognizable name.
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
