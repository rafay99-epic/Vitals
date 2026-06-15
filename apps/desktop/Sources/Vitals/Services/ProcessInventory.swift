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

            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard ok == 0 else { continue }

            let cpuTime = usage.ri_user_time + usage.ri_system_time
            currentCPUTime[pid] = cpuTime
            var cpuPercent = 0.0
            if hadPrevious, wallNanos > 0, let before = previousCPUTime[pid], cpuTime >= before {
                cpuPercent = Double(cpuTime - before) * Self.nanosPerTick / wallNanos * 100
            }

            processes.append(RunningProcess(
                id: pid,
                name: info.name,
                executablePath: info.executablePath,
                bundleURL: info.bundleURL,
                memoryBytes: usage.ri_phys_footprint,
                cpuPercent: cpuPercent,
                ownedByCurrentUser: ownedByMe
            ))
        }

        previousCPUTime = currentCPUTime
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
