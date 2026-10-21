import Foundation
import dnssd
import SystemConfiguration

/// Advertises the gateway's Wi-Fi listener as `_vitals._tcp` so the phone finds
/// this Mac without an address. Registration only: the gateway owns the socket
/// and mDNSResponder answers the queries.
///
/// Both the DNS-SD registration and the computer-name watch run on the main
/// queue, so their C callbacks can assume main-actor isolation. `RemoteModel`
/// calls `update(nil)` on every stop path, which releases both.
@MainActor
@Observable
final class LanAdvertiser {
    struct Advert: Equatable {
        let name: String
        let port: Int
        let key: String
        let channel: String
    }

    /// `LAN_SERVICE_TYPE` in packages/contracts/src/lan.ts.
    static let serviceType = "_vitals._tcp"

    /// What is registered right now. nil while not advertising.
    private(set) var advertised: Advert?

    @ObservationIgnored private var listener: GatewayStatus.Lan?
    @ObservationIgnored private var service: DNSServiceRef?
    @ObservationIgnored private var nameWatch: SCDynamicStore?

    /// Pass the latest `status.lan`, or nil to stop. Re-registers only when the
    /// port, key or computer name changed; a failed registration retries on the next call.
    func update(_ lan: GatewayStatus.Lan?) {
        listener = lan
        if lan == nil { stopWatchingName() } else { watchName() }
        let next = lan.map { Advert(name: Self.computerName, port: $0.port, key: $0.key, channel: Channel.current.rawValue) }
        guard next != advertised else { return }
        unregister()
        if let next { register(next) }
    }

    private func register(_ advert: Advert) {
        let txt = Self.txtRecord(advert)
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let error = txt.withUnsafeBytes { bytes in
            DNSServiceRegister(
                &ref, 0, 0, advert.name, Self.serviceType, nil, nil,
                UInt16(clamping: advert.port).bigEndian, UInt16(bytes.count), bytes.baseAddress,
                { _, _, error, _, _, _, context in
                    guard error != kDNSServiceErr_NoError, let context else { return }
                    let advertiser = Unmanaged<LanAdvertiser>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { advertiser.registrationFailed(error) }
                },
                context
            )
        }
        guard error == kDNSServiceErr_NoError, let ref else {
            Log.notice(.remote, "Bonjour registration failed (\(error))")
            return
        }
        let queued = DNSServiceSetDispatchQueue(ref, .main)
        guard queued == kDNSServiceErr_NoError else {
            DNSServiceRefDeallocate(ref)
            Log.notice(.remote, "Bonjour registration could not attach to the main queue (\(queued))")
            return
        }
        service = ref
        advertised = advert
        Log.notice(.remote, "advertising \(Self.serviceType) on port \(advert.port)")
    }

    private func unregister() {
        if let service { DNSServiceRefDeallocate(service) }
        service = nil
        advertised = nil
    }

    /// mDNSResponder restarted or rejected the record. Drop the dead ref; the next status update registers again.
    private func registrationFailed(_ error: DNSServiceErrorType) {
        Log.notice(.remote, "Bonjour registration stopped (\(error))")
        unregister()
    }

    // MARK: Computer name

    /// The service name and the TXT `n` follow the computer name, so renaming the Mac re-registers.
    private func watchName() {
        guard nameWatch == nil else { return }
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "Vitals.LanAdvertiser" as CFString, { _, _, info in
            guard let info else { return }
            let advertiser = Unmanaged<LanAdvertiser>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { advertiser.update(advertiser.listener) }
        }, &context) else { return }
        let keys = [SCDynamicStoreKeyCreateComputerName(nil)] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, nil), SCDynamicStoreSetDispatchQueue(store, .main) else { return }
        nameWatch = store
    }

    private func stopWatchingName() {
        if let nameWatch { SCDynamicStoreSetDispatchQueue(nameWatch, nil) }
        nameWatch = nil
    }

    /// Reads System Settings > Sharing directly. `Host.current()` can block on DNS.
    nonisolated static var computerName: String { SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac" }

    /// DNS-SD TXT wire format: each `key=value` entry prefixed by its byte length.
    nonisolated static func txtRecord(_ advert: Advert) -> [UInt8] {
        ["k=\(advert.key)", "n=\(advert.name)", "c=\(advert.channel)", "v=1"].flatMap { entry -> [UInt8] in
            let bytes = Array(entry.utf8.prefix(255))
            return [UInt8(bytes.count)] + bytes
        }
    }

    /// IPv4 addresses on `en*` interfaces that are up: what a phone on the same Wi-Fi dials.
    nonisolated static func lanAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        return sequence(first: first, next: { $0.pointee.ifa_next }).compactMap { entry -> String? in
            let ifa = entry.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  String(cString: ifa.ifa_name).hasPrefix("en") else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            return String(bytes: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
        }
    }
}
