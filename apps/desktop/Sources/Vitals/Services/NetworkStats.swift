import Foundation
import Darwin
import CoreWLAN
import SystemConfiguration

/// One physical network interface's live picture: its identity, the per-second
/// throughput derived by diffing kernel byte counters, the running totals since
/// boot, and whether the link is actually up. Rates only exist relative to a
/// previous reading, so a single `NetworkLink` from the first sample carries 0
/// rates — never a fabricated spike.
struct NetworkLink: Equatable, Sendable {
    enum Kind: Sendable { case wifi, ethernet, other }
    var name: String          // BSD name, "en0"
    var kind: Kind
    var displayName: String   // "Wi-Fi" / "Ethernet" / name
    var bytesInPerSec: Double
    var bytesOutPerSec: Double
    var totalBytesIn: UInt64   // since boot, from the kernel counters
    var totalBytesOut: UInt64
    var isActive: Bool         // IFF_UP && IFF_RUNNING
}

/// The Wi-Fi radio's association details, straight from CoreWLAN. Every field is
/// optional because the OS legitimately withholds some of them: modern macOS
/// returns a nil `ssid` unless the app holds Location permission, and an
/// unassociated radio reports no signal. We pass those nils through untouched —
/// an unknown SSID is honestly unknown, never a placeholder string.
struct WiFiInfo: Equatable, Sendable {
    var ssid: String?          // nil when macOS withholds it (needs Location permission)
    var rssi: Int?             // dBm
    var noise: Int?            // dBm
    var txRateMbps: Double?
    var channelNumber: Int?
    var channelBand: String?   // "2.4 GHz" / "5 GHz" / "6 GHz"
}

/// A full network reading for one tick: every counted physical interface (active
/// ones first), the summed throughput and running totals across them, the Wi-Fi
/// radio details when a Wi-Fi interface is powered on, and the default-route
/// interface when the system will tell us. Anything undeterminable is nil, not
/// guessed.
struct NetworkSnapshot: Sendable {
    var links: [NetworkLink]          // physical interfaces, active ones first
    var totalInPerSec: Double         // sum over counted interfaces
    var totalOutPerSec: Double
    var totalBytesIn: UInt64
    var totalBytesOut: UInt64
    var wifi: WiFiInfo?               // nil when no Wi-Fi interface is powered on
    var primaryInterfaceName: String? // default-route interface if determinable, else nil
}

/// Live per-interface network throughput, built from the kernel's 64-bit byte
/// counters. Sampled off the main thread by the sampler; **not** `@MainActor`.
///
/// Rates are deltas between consecutive `sample()` calls, so the instance holds
/// the previous counters and a monotonic timestamp. The **first** call has no
/// prior reading and reports 0 rates — honest, because a rate needs history.
///
/// Byte counters come from `sysctl(NET_RT_IFLIST2)` → `if_data64`, which are true
/// 64-bit values. `getifaddrs`' `if_data` counters wrap at 32 bits and are
/// deliberately not used here.
final class NetworkStats {
    /// Previous per-interface byte counters, keyed by BSD name, plus the
    /// monotonic timestamp they were read at — the two inputs a delta needs.
    private var previousCounters: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousTimestamp: UInt64?  // CLOCK_UPTIME_RAW nanoseconds

    /// The set of BSD names CoreWLAN considers Wi-Fi radios. Resolved once — the
    /// hardware doesn't change under us — so per-tick classification stays cheap.
    private lazy var wifiInterfaceNames: Set<String> = Set(CWWiFiClient.shared().interfaceNames() ?? [])

    /// BSD-name prefixes we never count toward throughput. These are either
    /// loopback (`lo`) or *virtual* interfaces that re-carry bytes which already
    /// crossed a physical `enX` link — a VPN tunnel (`utun`), AirDrop/AWDL
    /// (`awdl`, `llw`), a Thunderbolt/other bridge (`bridge`), classic tunnels
    /// (`gif`, `stf`), and Apple's internal helper interfaces (`ap`, `anpi`,
    /// `XHC`). Counting them would double-count the same traffic, so we keep only
    /// physical-style interfaces (`enX`: Wi-Fi, Ethernet, and Thunderbolt-bridge
    /// members, which are also `enX`).
    static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "ap", "anpi", "XHC"]

    /// True when a BSD interface name should be counted toward throughput — i.e.
    /// it isn't one of the virtual/loopback families above. Pure and internal so
    /// the double-count guard is unit-testable.
    static func isCountedInterface(_ name: String) -> Bool {
        !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    /// One reading. Rates are deltas versus the previous call; the first call
    /// reports 0 rates. Always returns a snapshot (empty links on total failure),
    /// never nil — the model can display "no interfaces" honestly.
    func sample() -> NetworkSnapshot {
        let counters = Self.readInterfaceCounters().filter { Self.isCountedInterface($0.name) }
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        // Elapsed since the last reading; 0 on the first call (no prior stamp),
        // which drives every rate to 0 via `CounterRate.perSecond`.
        let elapsed: TimeInterval = previousTimestamp.map { Double(now - $0) / 1_000_000_000 } ?? 0

        var links: [NetworkLink] = []
        for counter in counters {
            let previous = previousCounters[counter.name]
            let inRate = previous.map {
                CounterRate.perSecond(previous: $0.bytesIn, current: counter.bytesIn, elapsed: elapsed)
            } ?? 0
            let outRate = previous.map {
                CounterRate.perSecond(previous: $0.bytesOut, current: counter.bytesOut, elapsed: elapsed)
            } ?? 0
            let kind = classify(counter)
            links.append(NetworkLink(
                name: counter.name,
                kind: kind,
                displayName: displayName(for: counter.name, kind: kind),
                bytesInPerSec: inRate,
                bytesOutPerSec: outRate,
                totalBytesIn: counter.bytesIn,
                totalBytesOut: counter.bytesOut,
                isActive: counter.isActive
            ))
        }

        // Remember this tick's counters for the next delta.
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`: a duplicate BSD
        // name in the routing dump should never happen, but a monitor must not
        // crash on odd kernel output — keep the first record and move on.
        previousCounters = Dictionary(counters.map {
            ($0.name, (bytesIn: $0.bytesIn, bytesOut: $0.bytesOut))
        }, uniquingKeysWith: { first, _ in first })
        previousTimestamp = now

        // Active links first, then a stable name order so the list doesn't churn.
        links.sort { a, b in
            a.isActive == b.isActive ? a.name < b.name : a.isActive
        }

        let totalInPerSec = links.reduce(0) { $0 + $1.bytesInPerSec }
        let totalOutPerSec = links.reduce(0) { $0 + $1.bytesOutPerSec }
        let totalBytesIn = links.reduce(UInt64(0)) { $0 + $1.totalBytesIn }
        let totalBytesOut = links.reduce(UInt64(0)) { $0 + $1.totalBytesOut }

        return NetworkSnapshot(
            links: links,
            totalInPerSec: totalInPerSec,
            totalOutPerSec: totalOutPerSec,
            totalBytesIn: totalBytesIn,
            totalBytesOut: totalBytesOut,
            wifi: readWiFi(),
            primaryInterfaceName: readPrimaryInterface()
        )
    }

    // MARK: - Classification

    private func classify(_ counter: InterfaceCounter) -> NetworkLink.Kind {
        if wifiInterfaceNames.contains(counter.name) { return .wifi }
        if counter.ifType == UInt8(IFT_ETHER) && counter.name.hasPrefix("en") { return .ethernet }
        return .other
    }

    private func displayName(for name: String, kind: NetworkLink.Kind) -> String {
        switch kind {
        case .wifi:     return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .other:    return name
        }
    }

    // MARK: - Kernel byte counters (sysctl NET_RT_IFLIST2 → if_data64)

    /// One interface's identity + 64-bit byte counters, parsed from a
    /// `if_msghdr2` record.
    private struct InterfaceCounter {
        let name: String
        let ifType: UInt8
        let flags: Int32
        let bytesIn: UInt64
        let bytesOut: UInt64
        var isActive: Bool { (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 }
    }

    /// Walk the routing socket's interface list (`NET_RT_IFLIST2`) and pull the
    /// true 64-bit `ifi_ibytes` / `ifi_obytes` out of each `if_data64`. The
    /// buffer is a packed sequence of variable-length messages; we advance by
    /// each record's `ifm_msglen` and only decode the `RTM_IFINFO2` ones.
    private static func readInterfaceCounters() -> [InterfaceCounter] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            Log.errorOnce(.net, key: "iflist2-size", "sysctl NET_RT_IFLIST2 sizing failed")
            return []
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            Log.errorOnce(.net, key: "iflist2-read", "sysctl NET_RT_IFLIST2 read failed")
            return []
        }

        var result: [InterfaceCounter] = []
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<UInt16>.size <= length {
                let record = base + offset
                // if_msghdr2: ifm_msglen (u_short) @0, ifm_type (u_char) @3.
                let msglen = Int(record.loadUnaligned(as: UInt16.self))
                if msglen <= 0 || offset + msglen > length { break }
                let type = record.load(fromByteOffset: 3, as: UInt8.self)
                if Int32(type) == RTM_IFINFO2 {
                    let header = record.loadUnaligned(as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(header.ifm_index), &nameBuffer) != nil {
                        result.append(InterfaceCounter(
                            name: String(cString: nameBuffer),
                            ifType: header.ifm_data.ifi_type,
                            flags: header.ifm_flags,
                            bytesIn: header.ifm_data.ifi_ibytes,
                            bytesOut: header.ifm_data.ifi_obytes
                        ))
                    }
                }
                offset += msglen
            }
        }
        return result
    }

    // MARK: - Wi-Fi (CoreWLAN)

    /// The Wi-Fi radio's live association, or nil when the radio is powered off
    /// (no Wi-Fi to report). Every CoreWLAN read is guarded and left nil when the
    /// OS returns nothing — an unassociated radio reports no signal, and macOS
    /// withholds the SSID without Location permission; we never invent either.
    private func readWiFi() -> WiFiInfo? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return nil }
        let channel = interface.wlanChannel()
        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let txRate = interface.transmitRate()
        return WiFiInfo(
            ssid: interface.ssid(),
            rssi: rssi != 0 ? rssi : nil,
            noise: noise != 0 ? noise : nil,
            txRateMbps: txRate > 0 ? txRate : nil,
            channelNumber: channel?.channelNumber,
            channelBand: channel.flatMap { Self.bandString($0.channelBand) }
        )
    }

    private static func bandString(_ band: CWChannelBand) -> String? {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default:        return nil
        }
    }

    // MARK: - Default route

    /// The primary (default-route) interface name from SystemConfiguration's
    /// global IPv4 state, or nil when it can't be determined.
    private func readPrimaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Vitals.NetworkStats" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return value["PrimaryInterface"] as? String
    }
}

/// Pure, locale-independent formatting for network numbers. Base **1000** (the
/// networking convention, not 1024) and adaptive precision: bytes/sec render as
/// an integer of B/s, KB/s carries 0–1 decimals, MB/s and GB/s one decimal.
/// `String(format:)` uses the C locale, so the output is deterministic and
/// testable regardless of the user's region.
enum NetworkFormat {
    /// A throughput like "0 B/s", "540 KB/s", "1.2 MB/s".
    static func rate(_ bytesPerSec: Double) -> String {
        let value = (bytesPerSec.isFinite && bytesPerSec > 0) ? bytesPerSec : 0
        if value < 1000 { return "\(Int(value.rounded())) B/s" }
        let kb = value / 1000
        if kb < 1000 {
            // 0 decimals once we're into the hundreds; 1 decimal below, so small
            // rates keep a useful digit without cluttering big ones.
            return kb >= 100 ? "\(Int(kb.rounded())) KB/s" : "\(oneDecimal(kb)) KB/s"
        }
        let mb = kb / 1000
        if mb < 1000 { return "\(oneDecimal(mb)) MB/s" }
        return "\(oneDecimal(mb / 1000)) GB/s"
    }

    /// A menu-bar-width throughput like "0B", "540K", "1.2M" — the same tiers
    /// as `rate(_:)` with the unit shrunk to one letter (K/M/G of bytes per
    /// second), for surfaces where every point of width matters.
    static func compactRate(_ bytesPerSec: Double) -> String {
        let value = (bytesPerSec.isFinite && bytesPerSec > 0) ? bytesPerSec : 0
        if value < 1000 { return "\(Int(value.rounded()))B" }
        let kb = value / 1000
        if kb < 1000 { return kb >= 100 ? "\(Int(kb.rounded()))K" : "\(oneDecimal(kb))K" }
        let mb = kb / 1000
        if mb < 1000 { return "\(oneDecimal(mb))M" }
        return "\(oneDecimal(mb / 1000))G"
    }

    /// A byte total like "0 B", "1.4 GB". Integer B below 1 KB, one decimal above.
    static func bytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(bytes) B" }
        return "\(oneDecimal(value)) \(units[index])"
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
