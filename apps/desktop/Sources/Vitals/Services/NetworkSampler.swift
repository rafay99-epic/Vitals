import CoreWLAN
import Foundation
import SystemConfiguration

/// One reading of network activity: per-interface throughput plus the headline
/// rollup, session totals, the OS's primary interface, and Wi-Fi radio metadata.
/// Every rate is a real counter delta divided by elapsed time — never smoothed,
/// assumed, or invented. An idle link honestly reads 0 B/s.
struct NetworkSnapshot: Sendable {
    enum InterfaceKind: Sendable { case wifi, ethernet, vpn, other }

    struct InterfaceStats: Sendable, Identifiable {
        let name: String
        let kind: InterfaceKind
        let downBps: Double
        let upBps: Double
        var id: String { name }
    }

    struct WifiInfo: Sendable {
        // ssid is nil whenever CoreWLAN won't hand it over — Location permission
        // and (on this app's self-signed identity) Developer-ID gating both apply.
        // Pass the nil straight through; the UI shows "—", never a fabricated name.
        let ssid: String?
        let rssi: Int?
        let txRateMbps: Double?
        let channel: Int?
    }

    let downBps: Double            // rollup of physical interfaces only (wifi+ethernet)
    let upBps: Double
    let sessionDownBytes: UInt64   // accumulated physical deltas since sampler creation
    let sessionUpBytes: UInt64
    let primaryInterface: String?  // SCDynamicStore PrimaryInterface ("en0", "utun4", …)
    let interfaces: [InterfaceStats]   // active physical + vpn interfaces
    let wifi: WifiInfo?            // nil when Wi-Fi isn't an active interface
}

/// Samples per-interface byte counters and derives throughput. Holds the prior
/// counters + timestamp per interface (like `SoCPowerSampler`'s previous/elapsed
/// diff) and reports `nil` on the first call (no prior to diff against) or a total
/// read failure — never zeros dressed up as data.
///
/// Self-contained by design: it lives behind the `SensorSampler` actor, so its
/// mutable state is only ever touched from one executor. The per-interface
/// `sysctl`s run every tick (cheap); the heavier CoreWLAN interface-name lookup
/// and the `SCDynamicStore` primary-interface read are each behind their own
/// cache/one-time setup (below) rather than every tick.
///
/// The three (optionally four) providers are the testability seam — production
/// reads real kernel/framework state; tests inject fake counters and a fake clock.
final class NetworkSampler {
    struct RawCounters: Sendable {
        let name: String
        let inBytes: UInt64
        let outBytes: UInt64
    }

    private let counterProvider: () -> [RawCounters]
    private let primaryProvider: () -> String?
    private let wifiNamesProvider: () -> Set<String>
    private let wifiInfoProvider: () -> NetworkSnapshot.WifiInfo?

    private struct Baseline { let inBytes: UInt64; let outBytes: UInt64; let ts: Date }
    private var previous: [String: Baseline] = [:]

    private var sessionDown: UInt64 = 0
    private var sessionUp: UInt64 = 0

    // CoreWLAN reads are heavier than the sysctls, and RSSI/channel drift slowly,
    // so the Wi-Fi metadata is cached and refreshed at most this often.
    private var cachedWifi: NetworkSnapshot.WifiInfo?
    private var wifiReadAt = Date.distantPast
    private static let wifiRefreshInterval: TimeInterval = 15

    // Interface names essentially never change at runtime (unlike RSSI/channel),
    // so they're cached on the same TTL as the Wi-Fi metadata above rather than
    // re-walking CoreWLAN's `interfaceNames()` every tick. Only applied to the
    // production provider — an injected `wifiNamesProvider` (tests) is always
    // called fresh so a test that varies the set between samples never sees a
    // stale cache.
    private var cachedWifiNames: Set<String> = []
    private var wifiNamesReadAt = Date.distantPast
    private let usesDefaultWifiNamesProvider: Bool

    convenience init(counterProvider: (() -> [RawCounters])? = nil,
                     primaryProvider: (() -> String?)? = nil,
                     wifiNamesProvider: (() -> Set<String>)? = nil) {
        self.init(counterProvider: counterProvider,
                  primaryProvider: primaryProvider,
                  wifiNamesProvider: wifiNamesProvider,
                  wifiInfoProvider: nil)
    }

    /// Internal seam adding a Wi-Fi metadata provider so tests can exercise the
    /// SSID/RSSI passthrough without a live CoreWLAN read.
    init(counterProvider: (() -> [RawCounters])?,
         primaryProvider: (() -> String?)?,
         wifiNamesProvider: (() -> Set<String>)?,
         wifiInfoProvider: (() -> NetworkSnapshot.WifiInfo?)?) {
        self.counterProvider = counterProvider ?? { Self.readRawCounters() }
        self.primaryProvider = primaryProvider ?? { Self.readPrimaryInterface() }
        self.wifiNamesProvider = wifiNamesProvider ?? { Self.readWifiInterfaceNames() }
        self.wifiInfoProvider = wifiInfoProvider ?? { Self.readWifiInfo() }
        self.usesDefaultWifiNamesProvider = wifiNamesProvider == nil
    }

    func sample(now: Date = Date()) -> NetworkSnapshot? {
        let raw = counterProvider()
        // A truthful failure: lo0 exists on every Mac, so an empty read means the
        // sysctl walk itself failed. Report nil rather than a screen of zeros.
        guard !raw.isEmpty else { return nil }

        let isFirstSample = previous.isEmpty
        let wifiNames = cachedOrFreshWifiNames(now: now)

        var interfaces: [NetworkSnapshot.InterfaceStats] = []
        var rollupDown = 0.0, rollupUp = 0.0
        var sessionDownAdd: UInt64 = 0, sessionUpAdd: UInt64 = 0
        var newBaseline: [String: Baseline] = [:]

        for entry in raw {
            guard let kind = Self.classify(entry.name, wifiNames: wifiNames) else { continue }
            newBaseline[entry.name] = Baseline(inBytes: entry.inBytes, outBytes: entry.outBytes, ts: now)

            var downBps = 0.0, upBps = 0.0
            if let prev = previous[entry.name] {
                let elapsed = now.timeIntervalSince(prev.ts)
                // A drop in either counter means the interface bounced (Wi-Fi
                // toggled, VPN reconnected) and the kernel reset it: report 0 for
                // this tick and resync the baseline (already captured above) rather
                // than a negative or absurd spike. On non-Apple-signed builds the
                // counters also advance in ~1 KiB steps, so B/s is quantized to
                // ~1 KiB/tick — that's real resolution, not jitter to smooth away.
                if elapsed > 0, entry.inBytes >= prev.inBytes, entry.outBytes >= prev.outBytes {
                    let dIn = entry.inBytes - prev.inBytes
                    let dOut = entry.outBytes - prev.outBytes
                    downBps = Double(dIn) / elapsed
                    upBps = Double(dOut) / elapsed
                    if kind == .wifi || kind == .ethernet {
                        sessionDownAdd &+= dIn
                        sessionUpAdd &+= dOut
                    }
                }
            }

            // Physical links (wifi+ethernet) alone form the rollup: a VPN's bytes
            // already counted once as they egressed the physical interface.
            if kind == .wifi || kind == .ethernet {
                rollupDown += downBps
                rollupUp += upBps
            }

            // Include real, active links; skip the swarm of idle en1…enN and
            // unused tunnels that have never carried a byte. `.other` earns a slot
            // only by having traffic — same has-bytes test.
            if entry.inBytes > 0 || entry.outBytes > 0 {
                interfaces.append(.init(name: entry.name, kind: kind, downBps: downBps, upBps: upBps))
            }
        }

        previous = newBaseline

        // No prior counters yet — the deltas above are meaningless. Return nil so
        // the model shows nothing until the next tick produces a real rate.
        if isFirstSample { return nil }

        sessionDown &+= sessionDownAdd
        sessionUp &+= sessionUpAdd

        // With a VPN up this legitimately reports the utunN tunnel — that is the
        // OS's real outbound route, so we pass it through unaltered.
        let primary = primaryProvider()

        var wifi: NetworkSnapshot.WifiInfo?
        if interfaces.contains(where: { $0.kind == .wifi }) {
            if now.timeIntervalSince(wifiReadAt) >= Self.wifiRefreshInterval {
                cachedWifi = wifiInfoProvider()
                wifiReadAt = now
            }
            wifi = cachedWifi
        }

        return NetworkSnapshot(
            downBps: rollupDown,
            upBps: rollupUp,
            sessionDownBytes: sessionDown,
            sessionUpBytes: sessionUp,
            primaryInterface: primary,
            interfaces: interfaces,
            wifi: wifi
        )
    }

    /// The Wi-Fi interface-name set, refreshed at most every `wifiRefreshInterval`
    /// for the production provider; an injected provider (tests) is called fresh
    /// on every sample so seam-driven tests can't observe a stale cache.
    private func cachedOrFreshWifiNames(now: Date) -> Set<String> {
        guard usesDefaultWifiNamesProvider else { return wifiNamesProvider() }
        if now.timeIntervalSince(wifiNamesReadAt) >= Self.wifiRefreshInterval {
            cachedWifiNames = wifiNamesProvider()
            wifiNamesReadAt = now
        }
        return cachedWifiNames
    }

    /// Maps an interface name to its kind, or nil for names dropped entirely
    /// (loopback, AWDL/LLW backhaul, tunnel stubs, AP mode, bridges).
    static func classify(_ name: String, wifiNames: Set<String>) -> NetworkSnapshot.InterfaceKind? {
        for prefix in ["lo", "awdl", "llw", "gif", "stf", "ap", "bridge"] where name.hasPrefix(prefix) {
            return nil
        }
        if name.hasPrefix("utun") { return .vpn }
        if wifiNames.contains(name) { return .wifi }
        if name.hasPrefix("en") { return .ethernet }
        return .other
    }

    // MARK: - Real reads (production path)

    /// Reads 64-bit cumulative byte counters per interface via
    /// `sysctl(CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, <index>, IFDATA_GENERAL)`.
    /// `ifmibdata.ifmd_data` is a `struct if_data64` in the SDK, so `ifi_ibytes` /
    /// `ifi_obytes` are 64-bit — deliberately not `getifaddrs()`/`if_data`, whose
    /// 32-bit counters wrap at 4 GiB.
    static func readRawCounters() -> [RawCounters] {
        guard let head = if_nameindex() else { return [] }
        defer { if_freenameindex(head) }

        var result: [RawCounters] = []
        var p = head
        while p.pointee.if_index != 0 {   // the list terminates on a zero entry
            let index = p.pointee.if_index
            let name = String(cString: p.pointee.if_name)
            var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
            var data = ifmibdata()
            var len = MemoryLayout<ifmibdata>.stride
            if sysctl(&mib, u_int(mib.count), &data, &len, nil, 0) == 0 {
                result.append(RawCounters(name: name,
                                          inBytes: data.ifmd_data.ifi_ibytes,
                                          outBytes: data.ifmd_data.ifi_obytes))
            }
            p = p.advanced(by: 1)
        }
        return result
    }

    /// Created once, lazily, on first read and reused for the process's lifetime —
    /// `SCDynamicStoreCreate` is a real handshake with `configd`, not free, so
    /// recreating it every tick was wasted per-sample work (finding 5).
    private static let primaryInterfaceStore: SCDynamicStore? =
        SCDynamicStoreCreate(nil, "com.syntaxlab.vitals.network" as CFString, nil, nil)

    private static func readPrimaryInterface() -> String? {
        guard let store = primaryInterfaceStore,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    private static func readWifiInterfaceNames() -> Set<String> {
        Set(CWWiFiClient.shared().interfaceNames() ?? [])
    }

    private static func readWifiInfo() -> NetworkSnapshot.WifiInfo? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        let rssi = iface.rssiValue()
        let tx = iface.transmitRate()
        return NetworkSnapshot.WifiInfo(
            ssid: iface.ssid(),                     // nil when gated — pass through
            rssi: rssi == 0 ? nil : rssi,           // 0 = not associated / unavailable
            txRateMbps: tx > 0 ? tx : nil,
            channel: iface.wlanChannel()?.channelNumber
        )
    }
}
