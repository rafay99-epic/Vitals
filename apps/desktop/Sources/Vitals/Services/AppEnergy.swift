import Foundation
import AppKit

/// One app's aggregated energy use — helper processes folded under the app,
/// sleep assertions merged in. The Battery hub displays these; the history
/// logger persists a capped subset. UI-free.
struct AppEnergyUsage: Identifiable {
    /// Bundle path (or a `pid:` key for bundle-less processes) — stable across
    /// samples so SwiftUI rows keep their identity.
    let id: String
    let name: String
    /// The enclosing `.app`, for the icon. nil for daemons/helpers with no bundle.
    let bundleURL: URL?
    /// Reverse-DNS bundle id when resolvable — persisted for stable identity.
    let bundleID: String?
    /// Summed real watts across the app's processes. nil when none reported energy
    /// (then `impactIndex` ranks instead — we never invent a wattage).
    let avgWatts: Double?
    let cpuPercent: Double
    let wakeupsPerSec: Double
    /// Holds a system-sleep assertion → keeping the whole Mac awake.
    let preventsSystemSleep: Bool
    /// Holds a display-sleep assertion → keeping the screen on.
    let preventsDisplaySleep: Bool
    /// The assertion's description, e.g. "Playing a movie".
    let assertionReason: String?

    /// Activity-Monitor-style relative index, used to rank when real watts are
    /// absent. Unitless — never shown as watts.
    var impactIndex: Double { EnergyRate.impactIndex(cpuPercent: cpuPercent, wakeupsPerSec: wakeupsPerSec) }
    /// Ranking key: real watts when present, else the impact index.
    var rankValue: Double { avgWatts ?? impactIndex }
    var preventsSleep: Bool { preventsSystemSleep || preventsDisplaySleep }
}

/// Turns a raw process list + live sleep assertions into per-app energy usage.
/// The one place both the live Battery-hub view and the background history logger
/// build this, so they always agree on what "one app's energy" means.
enum AppEnergy {
    /// Group `processes` by owning app (folding helpers), sum their power / CPU /
    /// wakeups, and mark whoever holds a sleep assertion. `ownBundlePath` drops
    /// Vitals itself (safety rule). Returned sorted by rank (watts, else impact),
    /// highest first.
    static func usage(from processes: [RunningProcess],
                      assertions: [pid_t: [PowerAssertion]],
                      ownBundlePath: String) -> [AppEnergyUsage] {
        let visible = processes.filter { !$0.executablePath.hasPrefix(ownBundlePath) }
        let rows = groupProcessesByApp(visible, groupHelpers: true) { key, lead, items in
            let held = items.flatMap { assertions[$0.id] ?? [] }
            let watts = items.compactMap(\.avgWatts)
            return AppEnergyUsage(
                id: key,
                name: lead.name,
                bundleURL: lead.bundleURL,
                bundleID: lead.bundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier },
                avgWatts: watts.isEmpty ? nil : watts.reduce(0, +),
                cpuPercent: items.reduce(0) { $0 + $1.cpuPercent },
                wakeupsPerSec: items.reduce(0) { $0 + $1.wakeupsPerSec },
                preventsSystemSleep: held.contains { $0.preventsSystemSleep },
                preventsDisplaySleep: held.contains { $0.kind == .display },
                assertionReason: held.first(where: { $0.preventsSystemSleep })?.name ?? held.first?.name
            )
        }
        return rows.sorted { $0.rankValue > $1.rankValue }
    }

    /// The rows worth persisting to history: the top `limit` by rank, plus every
    /// app holding a system-sleep assertion (so sleep-blockers are always logged
    /// even when they aren't power-hungry).
    static func loggable(_ usage: [AppEnergyUsage], limit: Int = 20) -> [HistoryDatabase.AppEnergyRow] {
        let topIDs = Set(usage.prefix(limit).map(\.id))
        return usage
            .filter { topIDs.contains($0.id) || $0.preventsSystemSleep }
            .map { HistoryDatabase.AppEnergyRow(
                bundleID: $0.bundleID,
                name: $0.name,
                avgWatts: $0.avgWatts,
                cpuPercent: $0.cpuPercent,
                wakeupsPerSec: $0.wakeupsPerSec,
                preventsSleep: $0.preventsSystemSleep) }
    }
}
