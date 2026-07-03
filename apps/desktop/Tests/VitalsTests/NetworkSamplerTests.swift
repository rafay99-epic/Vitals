import Foundation
import Testing
@testable import Vitals

/// Locks the pure network-sampling logic through the injectable seams — no real
/// syscalls, a fake clock — plus one environment-dependent smoke test of the real
/// counter read. Every assertion is about honest rate math: exact B/s from counter
/// deltas, 0 on a counter reset, physical-only rollup, nil before there's a rate.
struct NetworkSamplerTests {
    typealias Raw = NetworkSampler.RawCounters

    /// Convenience: a sampler driven by a scripted sequence of counter reads.
    private func sampler(_ frames: [[Raw]],
                         wifiNames: Set<String> = [],
                         primary: String? = nil,
                         wifi: NetworkSnapshot.WifiInfo? = nil) -> (NetworkSampler, () -> Void) {
        var index = 0
        let s = NetworkSampler(
            counterProvider: {
                defer { index = min(index + 1, frames.count - 1) }
                return frames[index]
            },
            primaryProvider: { primary },
            wifiNamesProvider: { wifiNames },
            wifiInfoProvider: { wifi })
        return (s, {})
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Classification

    @Test func classificationDropsInternalAndTunnelStubs() {
        for name in ["lo0", "awdl0", "llw0", "gif0", "stf0", "ap1", "bridge0"] {
            #expect(NetworkSampler.classify(name, wifiNames: []) == nil)
        }
    }

    @Test func utunIsVpn() {
        #expect(NetworkSampler.classify("utun4", wifiNames: []) == .vpn)
    }

    @Test func wifiNameSetWins() {
        #expect(NetworkSampler.classify("en0", wifiNames: ["en0"]) == .wifi)
    }

    @Test func enFallsBackToEthernet() {
        #expect(NetworkSampler.classify("en5", wifiNames: ["en0"]) == .ethernet)
    }

    @Test func unknownIsOther() {
        #expect(NetworkSampler.classify("pdp_ip0", wifiNames: []) == .other)
    }

    // MARK: - Rate math

    @Test func firstSampleReturnsNil() {
        let (s, _) = sampler([[Raw(name: "en0", inBytes: 100, outBytes: 50)]], wifiNames: ["en0"])
        #expect(s.sample(now: t0) == nil)
    }

    @Test func exactBytesPerSecondOverTwoSamples() {
        let (s, _) = sampler([
            [Raw(name: "en0", inBytes: 1_000, outBytes: 500)],
            [Raw(name: "en0", inBytes: 3_000, outBytes: 1_500)],
        ], wifiNames: ["en0"])
        _ = s.sample(now: t0)
        let snap = s.sample(now: t0.addingTimeInterval(2))
        // (3000-1000)/2s = 1000 B/s down, (1500-500)/2 = 500 B/s up
        #expect(snap?.downBps == 1_000)
        #expect(snap?.upBps == 500)
    }

    @Test func counterResetYieldsZeroAndResyncs() {
        let (s, _) = sampler([
            [Raw(name: "en0", inBytes: 10_000, outBytes: 10_000)],
            [Raw(name: "en0", inBytes: 500, outBytes: 500)],      // bounced: lower than before
            [Raw(name: "en0", inBytes: 2_500, outBytes: 1_500)],  // resumes from the resynced baseline
        ], wifiNames: ["en0"])
        _ = s.sample(now: t0)
        let reset = s.sample(now: t0.addingTimeInterval(1))
        #expect(reset?.downBps == 0)
        #expect(reset?.upBps == 0)
        #expect(reset?.sessionDownBytes == 0)   // nothing accumulated across a reset
        #expect(reset?.sessionUpBytes == 0)

        let resumed = s.sample(now: t0.addingTimeInterval(2))
        // baseline resynced to 500/500, so (2500-500)/1 = 2000, (1500-500)/1 = 1000
        #expect(resumed?.downBps == 2_000)
        #expect(resumed?.upBps == 1_000)
    }

    // MARK: - Rollup + session

    @Test func physicalRollupExcludesVpnAndOther() {
        let frame = [
            Raw(name: "en0", inBytes: 0, outBytes: 0),   // wifi
            Raw(name: "en1", inBytes: 0, outBytes: 0),   // ethernet
            Raw(name: "utun0", inBytes: 0, outBytes: 0), // vpn — excluded from rollup
            Raw(name: "pdp_ip0", inBytes: 0, outBytes: 0), // other — excluded from rollup
        ]
        let next = [
            Raw(name: "en0", inBytes: 1_000, outBytes: 100),
            Raw(name: "en1", inBytes: 2_000, outBytes: 200),
            Raw(name: "utun0", inBytes: 9_000, outBytes: 900),
            Raw(name: "pdp_ip0", inBytes: 9_000, outBytes: 900),
        ]
        let (s, _) = sampler([frame, next], wifiNames: ["en0"])
        _ = s.sample(now: t0)
        let snap = s.sample(now: t0.addingTimeInterval(1))
        // only en0 + en1: (1000+2000) down, (100+200) up. VPN/other ignored.
        #expect(snap?.downBps == 3_000)
        #expect(snap?.upBps == 300)
    }

    @Test func sessionTotalsAccumulateAcrossSamples() {
        let (s, _) = sampler([
            [Raw(name: "en0", inBytes: 0, outBytes: 0)],
            [Raw(name: "en0", inBytes: 100, outBytes: 10)],
            [Raw(name: "en0", inBytes: 300, outBytes: 30)],
            [Raw(name: "en0", inBytes: 600, outBytes: 60)],
        ], wifiNames: ["en0"])
        _ = s.sample(now: t0)
        _ = s.sample(now: t0.addingTimeInterval(1))
        _ = s.sample(now: t0.addingTimeInterval(2))
        let snap = s.sample(now: t0.addingTimeInterval(3))
        #expect(snap?.sessionDownBytes == 600)   // 100 + 200 + 300
        #expect(snap?.sessionUpBytes == 60)      // 10 + 20 + 30
    }

    @Test func sessionTotalsExcludeVpn() {
        let (s, _) = sampler([
            [Raw(name: "utun0", inBytes: 0, outBytes: 0)],
            [Raw(name: "utun0", inBytes: 5_000, outBytes: 5_000)],
        ], wifiNames: [])
        _ = s.sample(now: t0)
        let snap = s.sample(now: t0.addingTimeInterval(1))
        #expect(snap?.sessionDownBytes == 0)   // VPN bytes never enter the session rollup
        #expect(snap?.sessionUpBytes == 0)
    }

    // MARK: - Interface list

    @Test func idleUnusedInterfacesAreOmitted() {
        let frame = [
            Raw(name: "en0", inBytes: 1_000, outBytes: 1_000), // has traffic
            Raw(name: "en3", inBytes: 0, outBytes: 0),         // never used
            Raw(name: "lo0", inBytes: 9_000, outBytes: 9_000), // dropped kind
        ]
        let (s, _) = sampler([frame, frame], wifiNames: ["en0"])
        _ = s.sample(now: t0)
        let snap = s.sample(now: t0.addingTimeInterval(1))
        #expect(snap?.interfaces.map(\.name) == ["en0"])
        #expect(snap?.interfaces.first?.kind == .wifi)
    }

    @Test func vpnIsListedButNotInRollup() {
        let (s, _) = sampler([
            [Raw(name: "utun4", inBytes: 100, outBytes: 100)],
            [Raw(name: "utun4", inBytes: 200, outBytes: 200)],
        ], wifiNames: [])
        _ = s.sample(now: t0)
        let snap = s.sample(now: t0.addingTimeInterval(1))
        #expect(snap?.interfaces.map(\.name) == ["utun4"])
        #expect(snap?.interfaces.first?.kind == .vpn)
        #expect(snap?.downBps == 0)   // not physical → no rollup contribution
    }

    // MARK: - Passthroughs

    @Test func primaryInterfacePassesThrough() {
        let (s, _) = sampler([
            [Raw(name: "en0", inBytes: 0, outBytes: 0)],
            [Raw(name: "en0", inBytes: 1, outBytes: 1)],
        ], wifiNames: ["en0"], primary: "utun4")
        _ = s.sample(now: t0)
        #expect(s.sample(now: t0.addingTimeInterval(1))?.primaryInterface == "utun4")
    }

    @Test func wifiNilSsidPassesThrough() {
        let info = NetworkSnapshot.WifiInfo(ssid: nil, rssi: -55, txRateMbps: 104, channel: 8)
        let (s, _) = sampler([
            [Raw(name: "en0", inBytes: 1_000, outBytes: 1_000)],
            [Raw(name: "en0", inBytes: 2_000, outBytes: 2_000)],
        ], wifiNames: ["en0"], primary: "en0", wifi: info)
        _ = s.sample(now: t0)
        let snap = s.sample(now: t0.addingTimeInterval(1))
        #expect(snap?.wifi?.ssid == nil)
        #expect(snap?.wifi?.rssi == -55)
        #expect(snap?.wifi?.channel == 8)
    }

    @Test func wifiNilWhenNoWifiInterface() {
        let (s, _) = sampler([
            [Raw(name: "en1", inBytes: 1_000, outBytes: 1_000)],   // ethernet, not wifi
            [Raw(name: "en1", inBytes: 2_000, outBytes: 2_000)],
        ], wifiNames: [], wifi: NetworkSnapshot.WifiInfo(ssid: "x", rssi: -1, txRateMbps: 1, channel: 1))
        _ = s.sample(now: t0)
        #expect(s.sample(now: t0.addingTimeInterval(1))?.wifi == nil)
    }

    @Test func emptyReadIsTotalFailureNotZeros() {
        let (s, _) = sampler([[]])
        #expect(s.sample(now: t0) == nil)
    }

    // MARK: - Real read (environment-dependent smoke test)

    /// Not seam-driven: exercises the production `sysctl` walk. lo0 exists on every
    /// Mac, so a working read is never empty and always includes it. Environment-
    /// dependent by nature, but should pass on any macOS host.
    @Test func realCounterReadReturnsPlausibleInterfaces() {
        let counters = NetworkSampler.readRawCounters()
        #expect(!counters.isEmpty)
        #expect(counters.contains { $0.name == "lo0" })
        for c in counters {
            #expect(!c.name.isEmpty)
        }
    }
}
