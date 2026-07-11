import Foundation
import Darwin

/// One running process. `memoryBytes` is the physical footprint — the same
/// number Activity Monitor shows under "Memory". `cpuPercent` is computed from
/// CPU-time deltas between samples (100% = one core fully busy).
struct RunningProcess: Identifiable {
    let id: pid_t
    let name: String
    let executablePath: String
    /// The enclosing `.app` bundle, when the executable lives inside one — used
    /// to group an app's many helper processes under the app itself.
    let bundleURL: URL?
    let memoryBytes: UInt64
    var cpuPercent: Double
    /// Average power drawn since the previous sample, in watts, from the
    /// process's own energy counter (`rusage_info_v6.ri_energy_nj`). A real
    /// hardware reading — nil until a second sample yields a delta, or when the
    /// OS reports no energy for this process (then the Energy-Impact index is
    /// used instead of inventing a wattage).
    var avgWatts: Double?
    /// Idle + interrupt wakeups per second since the previous sample. Each
    /// wakeup pulls the CPU out of a low-power state, so this is a real driver of
    /// battery drain and the basis for the Energy-Impact fallback.
    var wakeupsPerSec: Double
    /// Owned by the user running Vitals → killable without admin rights.
    let ownedByCurrentUser: Bool
}

/// Lists running processes with per-process CPU and memory. UI-free, and an
/// actor so the per-process syscall sweep (a few hundred `proc_*` calls) never
/// runs on the main thread — same discipline as `SensorSampler`.
actor ProcessInventory {
    /// A process's identity — path, name, bundle, owner — which never changes
    /// for a given pid. Cached so steady-state samples skip the costly lookups
    /// (proc_pidpath + the disk-touching display-name resolve) and just read
    /// the live cpu/memory.
    private struct StaticInfo {
        let name: String
        let executablePath: String
        let bundleURL: URL?
        let uid: uid_t
    }

    private var staticCache: [pid_t: StaticInfo] = [:]
    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousEnergy: [pid_t: UInt64] = [:]
    private var previousWakeups: [pid_t: UInt64] = [:]
    /// Per-pid process-start time (`ri_proc_start_abstime`). If it changes, the
    /// pid was reused by a different process and last sample's cumulative
    /// counters must not be diffed against this one.
    private var previousStart: [pid_t: UInt64] = [:]
    private var previousSampleAt: UInt64 = 0
    private let currentUID = getuid()

    private static let nanosPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    /// Snapshot every process. With `includeSystem` false (the default) only the
    /// current user's processes are returned — the apps you'd actually want to
    /// quit, without the root/daemon noise. Returns nil if the process list
    /// can't be read at all (restricted environment), distinct from an empty list.
    func sample(includeSystem: Bool) -> [RunningProcess]? {
        let now = mach_absolute_time()
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0, pidCount < 100_000 else { return nil }
        let capacity = Int(pidCount) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteSize = capacity * MemoryLayout<pid_t>.size
        guard byteSize <= Int(Int32.max) else { return nil }
        let filled = proc_listallpids(&pids, Int32(byteSize))
        guard filled > 0 else { return nil }

        let hadPrevious = previousSampleAt > 0 && now > previousSampleAt
        let wallNanos = Double(now - previousSampleAt) * Self.nanosPerTick
        var currentCPUTime: [pid_t: UInt64] = [:]
        var currentEnergy: [pid_t: UInt64] = [:]
        var currentWakeups: [pid_t: UInt64] = [:]
        var currentStart: [pid_t: UInt64] = [:]
        var liveStatic: [pid_t: StaticInfo] = [:]
        var processes: [RunningProcess] = []

        for pid in pids.prefix(Int(filled)) where pid > 0 {
            // Owner first (cheap) so others' processes are skipped before the
            // costlier path/name lookups.
            let uid: uid_t
            if let cached = staticCache[pid] {
                uid = cached.uid
            } else if let looked = ownerUID(of: pid) {
                uid = looked
            } else {
                continue
            }
            let ownedByMe = uid == currentUID
            if !includeSystem && !ownedByMe { continue }

            // Resolve identity once per pid; reuse it on later samples.
            let info: StaticInfo
            if let cached = staticCache[pid] {
                info = cached
            } else {
                let path = executablePath(of: pid)
                info = StaticInfo(
                    name: Self.displayName(path: path),
                    executablePath: path,
                    bundleURL: Self.bundleURL(forExecutablePath: path),
                    uid: uid
                )
            }
            liveStatic[pid] = info

            // v6 (the current rusage revision) adds the per-process energy
            // counter and wakeup tallies on top of every v4 field.
            var usage = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard ok == 0 else { continue }

            let cpuTime = usage.ri_user_time + usage.ri_system_time
            let energy = usage.ri_energy_nj
            let wakeups = usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups
            let start = usage.ri_proc_start_abstime
            currentCPUTime[pid] = cpuTime
            currentEnergy[pid] = energy
            currentWakeups[pid] = wakeups
            currentStart[pid] = start

            // Only diff cumulative counters when the previous sample was the
            // *same* process at this pid (start time unchanged).
            let sameProcess = previousStart[pid] == start
            var cpuPercent = 0.0
            var avgWatts: Double? = nil
            var wakeupsPerSec = 0.0
            if hadPrevious, wallNanos > 0, sameProcess {
                if let before = previousCPUTime[pid], cpuTime >= before {
                    cpuPercent = Double(cpuTime - before) * Self.nanosPerTick / wallNanos * 100
                }
                if let before = previousEnergy[pid], energy > before {
                    avgWatts = EnergyRate.watts(energyDeltaNanojoules: energy - before, overNanoseconds: wallNanos)
                }
                if let before = previousWakeups[pid], wakeups >= before {
                    wakeupsPerSec = EnergyRate.perSecond(delta: wakeups - before, overNanoseconds: wallNanos)
                }
            }

            processes.append(RunningProcess(
                id: pid,
                name: info.name,
                executablePath: info.executablePath,
                bundleURL: info.bundleURL,
                memoryBytes: usage.ri_phys_footprint,
                cpuPercent: cpuPercent,
                avgWatts: avgWatts,
                wakeupsPerSec: wakeupsPerSec,
                ownedByCurrentUser: ownedByMe
            ))
        }

        previousCPUTime = currentCPUTime
        previousEnergy = currentEnergy
        previousWakeups = currentWakeups
        previousStart = currentStart
        previousSampleAt = now
        staticCache = liveStatic // drop dead pids
        return processes
    }

    // MARK: Per-process lookups

    private func ownerUID(of pid: pid_t) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard read == size else { return nil }
        return info.pbi_uid
    }

    private func executablePath(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// The `.app` bundle a path lives in, if any — e.g. an executable at
    /// `…/Brave Browser.app/Contents/Frameworks/…/Helper` maps to `Brave Browser.app`.
    nonisolated private static func bundleURL(forExecutablePath path: String) -> URL? {
        guard let range = path.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(path[path.startIndex..<range.lowerBound]) + ".app")
    }

    /// A friendly name: the `.app` bundle's display name, else the executable
    /// file name (skipping version-like names such as "125.0.6422").
    nonisolated private static func displayName(path: String) -> String {
        if let bundle = bundleURL(forExecutablePath: path) {
            return FileManager.default.displayName(atPath: bundle.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        let components = path.split(separator: "/")
        guard let last = components.last else { return "Process" }
        let executable = String(last)
        // A binary named like a version ("2.1.177") is meaningless on its own —
        // its parent folder is the recognizable name.
        let isVersionLike = !executable.isEmpty && executable.allSatisfy { $0.isNumber || $0 == "." }
        if isVersionLike, components.count >= 2 {
            return String(components[components.count - 2])
        }
        return executable.isEmpty ? "Process" : executable
    }
}

/// Turns cumulative rusage counter deltas into per-second rates. Pure, so the
/// energy/wakeup math is verified without live sampling.
enum EnergyRate {
    /// Average watts from an energy delta (nanojoules) over a wall interval
    /// (nanoseconds): nJ/ns == J/s == W. nil when the interval is non-positive
    /// or the counter didn't advance.
    static func watts(energyDeltaNanojoules: UInt64, overNanoseconds ns: Double) -> Double? {
        guard ns > 0, energyDeltaNanojoules > 0 else { return nil }
        return Double(energyDeltaNanojoules) / ns
    }

    /// A count delta as a per-second rate (e.g. wakeups/s).
    static func perSecond(delta: UInt64, overNanoseconds ns: Double) -> Double {
        guard ns > 0 else { return 0 }
        return Double(delta) * 1_000_000_000 / ns
    }

    /// Activity-Monitor-style relative Energy-Impact index, used *only* as a
    /// fallback when the OS reports no real per-process energy: CPU load plus a
    /// wakeup penalty. Unitless and relative — never shown as watts.
    /// ponytail: 0.4 wakeup weight is a heuristic (Apple's real formula is
    /// private); tune this constant if the ranking looks off against Activity Monitor.
    static func impactIndex(cpuPercent: Double, wakeupsPerSec: Double) -> Double {
        cpuPercent + wakeupsPerSec * 0.4
    }
}

/// Buckets processes by the `.app` they belong to (helper processes folded under
/// their app), or by pid when ungrouped or bundle-less — preserving first-seen
/// order. `combine` builds one row per bucket from its lead process and members.
/// Shared by the Processes tab and the Battery hub's app-energy list so both
/// agree on what counts as "one app".
func groupProcessesByApp<Row>(
    _ processes: [RunningProcess],
    groupHelpers: Bool,
    combine: (_ key: String, _ lead: RunningProcess, _ items: [RunningProcess]) -> Row
) -> [Row] {
    var buckets: [String: [RunningProcess]] = [:]
    var order: [String] = []
    for process in processes {
        let key = (groupHelpers ? process.bundleURL?.path : nil) ?? "pid:\(process.id)"
        if buckets[key] == nil { order.append(key) }
        buckets[key, default: []].append(process)
    }
    return order.map { key in
        let items = buckets[key]!
        return combine(key, items[0], items)
    }
}
