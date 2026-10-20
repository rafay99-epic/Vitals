import Foundation

enum ProcessGroup: String, CaseIterable, Sendable {
    case agents, emulators, devServers, browsers, other, protected
}

struct ProcessGroups {
    struct Totals: Equatable, Sendable {
        let group: ProcessGroup
        var count: Int
        var cpuPercent: Double
        var memory: UInt64
    }

    struct Classified: Sendable {
        let groupByPid: [pid_t: ProcessGroup]
        let totals: [Totals]

        func group(of pid: pid_t) -> ProcessGroup { groupByPid[pid] ?? .other }
        func totals(for group: ProcessGroup) -> Totals { totals.first { $0.group == group } ?? Totals(group: group, count: 0, cpuPercent: 0, memory: 0) }
    }

    static let agentNames: Set<String> = [
        "claude", "codex", "opencode", "opencode.exe", "cursor-agent", "gemini", "aider", "goose", "amp", "crush", "qwen",
    ]
    static let agentPathMarkers = ["/claude/versions/", "/.codex/", "/codex/bin/", "/opencode/bin/"]
    static let emulatorNames: Set<String> = [
        "qemu-system-aarch64", "qemu-system-x86_64", "emulator", "Simulator", "launchd_sim",
    ]
    static let devServerNames: Set<String> = [
        "node", "bun", "deno", "java", "xcodebuild", "swift-frontend", "gradle", "ruby", "python3", "python", "esbuild", "watchman",
    ]
    static let browserPrefixes = ["Google Chrome", "Brave Browser", "Arc", "Firefox", "Safari", "Microsoft Edge", "com.apple.WebKit"]
    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Finder", "Dock", "SystemUIServer", "ControlCenter",
        "Tailscale", "tailscaled", "IPNExtension", "io.tailscale.ipn.macsys.network-extension", "vitals-gateway",
        "Vitals", "Vitals Dev", "Vitals Nightly", "coreaudiod", "mds", "mds_stores",
    ]

    static func classify(_ rows: [ProcessSampler.Row], ownUid: uid_t = getuid(), ownPid: pid_t = getpid()) -> Classified {
        let byPid = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var memo: [pid_t: ProcessGroup] = [:]

        func base(_ row: ProcessSampler.Row) -> ProcessGroup? {
            if row.uid != ownUid || row.pid == ownPid || row.ppid == ownPid || protectedNames.contains(row.name) || row.path.hasPrefix("/System/") {
                return .protected
            }
            if agentNames.contains(row.name) || agentPathMarkers.contains(where: row.path.contains) { return .agents }
            if emulatorNames.contains(row.name) { return .emulators }
            return nil
        }

        func resolve(_ pid: pid_t, depth: Int) -> ProcessGroup {
            if let cached = memo[pid] { return cached }
            guard let row = byPid[pid] else { return .other }
            let group: ProcessGroup
            if let direct = base(row) {
                group = direct
            } else {
                let inherited = depth < 32 && row.ppid > 1 ? resolve(row.ppid, depth: depth + 1) : .other
                if inherited == .agents || inherited == .emulators {
                    group = inherited
                } else if browserPrefixes.contains(where: row.name.hasPrefix) || inherited == .browsers {
                    group = .browsers
                } else if devServerNames.contains(row.name) {
                    group = .devServers
                } else {
                    group = .other
                }
            }
            memo[pid] = group
            return group
        }

        var totals = Dictionary(uniqueKeysWithValues: ProcessGroup.allCases.map { ($0, Totals(group: $0, count: 0, cpuPercent: 0, memory: 0)) })
        for row in rows {
            let group = resolve(row.pid, depth: 0)
            totals[group]?.count += 1
            totals[group]?.cpuPercent += row.cpuPercent
            totals[group]?.memory += row.memory
        }
        return Classified(groupByPid: memo, totals: ProcessGroup.allCases.compactMap { totals[$0] })
    }
}
