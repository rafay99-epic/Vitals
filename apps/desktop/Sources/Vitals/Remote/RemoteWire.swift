import Foundation

struct WireMac: Codable, Equatable, Sendable {
    let name: String
    let model: String
    let chip: String
    let os: String
    let coreCount: Int
    let memoryBytes: Double
    let hasBattery: Bool
    let hasFans: Bool
    let vitalsVersion: String
    let channel: String
}

struct WireKeepAwake: Codable, Equatable, Sendable {
    let active: Bool
    let display: Bool
    @Nullable var until: Int64?
    @Nullable var whileProcess: ProcessRef?

    static let off = WireKeepAwake(active: false, display: false, until: nil, whileProcess: nil)
}

/// The Mac's output volume (0...1) and mute. Nil when the output doesn't expose one.
struct WireAudio: Codable, Equatable, Sendable {
    @Nullable var volume: Double?
    @Nullable var muted: Bool?
}

struct WireCore: Codable, Equatable, Sendable {
    let id: Int
    let percent: Double
    let isPerformance: Bool
}

struct WireCPU: Codable, Equatable, Sendable {
    @Nullable var overall: Double?
    @Nullable var performance: Double?
    @Nullable var efficiency: Double?
    let perCore: [WireCore]
}

struct WireGPU: Codable, Equatable, Sendable {
    @Nullable var utilization: Double?
    @Nullable var memoryUsedBytes: Double?
    @Nullable var coreCount: Int?
    var rendererUtilization: Double?
    var tilerUtilization: Double?
    var memoryTotalBytes: Double?
}

struct WireSensor: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let kind: String
    let celsius: Double
}

struct WireThermal: Codable, Equatable, Sendable {
    let state: String
    @Nullable var cpuC: Double?
    @Nullable var gpuC: Double?
    @Nullable var storageC: Double?
    @Nullable var batteryC: Double?
    let sensors: [WireSensor]
}

struct WireFan: Codable, Equatable, Sendable {
    let id: Int
    let rpm: Double
    let minRpm: Double
    let maxRpm: Double
}

struct WireMemory: Codable, Equatable, Sendable {
    let totalBytes: Double
    let usedBytes: Double
    let appBytes: Double
    let wiredBytes: Double
    let compressedBytes: Double
    let cachedBytes: Double
    let freeBytes: Double
    let swapUsedBytes: Double
    let swapTotalBytes: Double
    let pressure: String
}

struct WireBattery: Codable, Equatable, Sendable {
    let percent: Double
    let charging: Bool
    let externalPower: Bool
    @Nullable var watts: Double?
    @Nullable var timeRemainingMinutes: Int?
    @Nullable var cycleCount: Int?
    @Nullable var healthPercent: Double?
    @Nullable var temperatureC: Double?
    let condition: String
    var fullyCharged: Bool?
    var designCapacityMah: Int?
    var maxCapacityMah: Int?
    var remainingCapacityMah: Int?
    var designCycleCount: Int?
    var voltage: Double?
    var amperage: Double?
    var adapter: WireAdapter?
}

struct WireAdapter: Codable, Equatable, Sendable {
    var watts: Double?
    var name: String?
    let wireless: Bool
    var deliveredWatts: Double?
    var voltage: Double?
    var amperage: Double?
}

struct WirePower: Codable, Equatable, Sendable {
    let cpuWatts: Double
    let gpuWatts: Double
    let aneWatts: Double
}

struct WireNetwork: Codable, Equatable, Sendable {
    let inBytesPerSec: Double
    let outBytesPerSec: Double
    @Nullable var wifiRssi: Int?
    @Nullable var primaryInterface: String?
    var totalInBytes: Double?
    var totalOutBytes: Double?
    var links: [WireLink]?
    var wifi: WireWifi?
}

struct WireLink: Codable, Equatable, Sendable {
    let name: String
    let label: String
    let kind: String
    let inBytesPerSec: Double
    let outBytesPerSec: Double
    let active: Bool
}

struct WireWifi: Codable, Equatable, Sendable {
    var ssid: String?
    var rssi: Int?
    var noise: Int?
    var txRateMbps: Double?
    var channel: Int?
    var band: String?
}

struct WireDisk: Codable, Equatable, Sendable {
    let readBytesPerSec: Double
    let writeBytesPerSec: Double
    var freeBytes: Double?
    var totalBytes: Double?
    var volume: String?
    var health: WireDriveHealth?
}

struct WireDriveHealth: Codable, Equatable, Sendable {
    var model: String?
    let wearPercent: Int
    let readBytes: Double
    let writtenBytes: Double
    let powerOnHours: Int
    let unsafeShutdowns: Int
    let sparePercent: Int
    var celsius: Double?
    let warning: Bool
}

struct WireSample: Codable, Equatable, Sendable {
    let seq: Int
    let at: Int64
    var cpu: WireCPU?
    var gpu: WireGPU?
    var thermal: WireThermal?
    var fans: [WireFan]?
    var memory: WireMemory?
    var battery: Nullable<WireBattery>?
    var power: Nullable<WirePower>?
    var systemWatts: Double?
    var network: WireNetwork?
    var disk: WireDisk?
}

struct WireProcessRow: Codable, Equatable, Sendable {
    let pid: Int32
    let startTimeMs: Int64
    let name: String
    let group: String
    let cpuPercent: Double
    let memoryBytes: Double
    let throttled: Bool
    let paused: Bool
}

struct WireGroupTotals: Codable, Equatable, Sendable {
    let group: String
    let count: Int
    let cpuPercent: Double
    let memoryBytes: Double
}

struct WireProcesses: Codable, Equatable, Sendable {
    let at: Int64
    let rows: [WireProcessRow]
    let groups: [WireGroupTotals]
}

struct WireCalmPlan: Codable, Equatable, Sendable {
    let actions: [ProcessAction]
    let summary: String
}

struct WireAlert: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let rule: String
    let severity: String
    let summary: String
    let raisedAt: Int64
    @Nullable var clearedAt: Int64?
    let groups: [WireGroupTotals]
    let plan: WireCalmPlan
}

struct WireGuardState: Codable, Equatable, Sendable {
    let settings: GuardSettings
    let pressure: String
    let thermal: String
    let swapUsedBytes: Double
    let groups: [WireGroupTotals]
    let active: [WireAlert]
    let calmApplied: Bool
}

struct WireReceipt: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case pending, running, done, failed, cancelled, rejected }
    let id: String
    let kind: String
    let deviceId: String
    let status: Status
    let createdAt: Int64
    @Nullable var deadlineAt: Int64?
    @Nullable var finishedAt: Int64?
    @Nullable var error: String?
}

struct WireRunningApp: Codable, Equatable, Sendable {
    let pid: Int32
    @Nullable var bundleId: String?
    let name: String
    let active: Bool
    let hidden: Bool
}

struct WireEmulator: Codable, Equatable, Sendable {
    let kind: String
    let id: String
    let name: String
    @Nullable var pid: Int32?
}

struct WireApps: Codable, Equatable, Sendable {
    let running: [WireRunningApp]
    let emulators: [WireEmulator]
}

struct WireBucket: Codable, Equatable, Sendable {
    let t: Int64
    let min: Double
    let avg: Double
    let max: Double
}

struct WireSeries: Codable, Equatable, Sendable {
    let name: String
    let buckets: [WireBucket]
}

enum WireEvent: Equatable, Sendable {
    case willSleep(at: Int64)
    case didWake(at: Int64)
    case willPowerOff(at: Int64)
    case thermalChanged(at: Int64, state: String)
    case keepAwakeChanged(at: Int64, state: WireKeepAwake)
    case alertRaised(at: Int64, alert: WireAlert)
    case alertCleared(at: Int64, alert: WireAlert)
}

extension WireEvent: Encodable {
    private enum Keys: String, CodingKey { case _tag, at, state, alert }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .willSleep(at):
            try c.encode("WillSleep", forKey: ._tag)
            try c.encode(at, forKey: .at)
        case let .didWake(at):
            try c.encode("DidWake", forKey: ._tag)
            try c.encode(at, forKey: .at)
        case let .willPowerOff(at):
            try c.encode("WillPowerOff", forKey: ._tag)
            try c.encode(at, forKey: .at)
        case let .thermalChanged(at, state):
            try c.encode("ThermalChanged", forKey: ._tag)
            try c.encode(at, forKey: .at)
            try c.encode(state, forKey: .state)
        case let .keepAwakeChanged(at, state):
            try c.encode("KeepAwakeChanged", forKey: ._tag)
            try c.encode(at, forKey: .at)
            try c.encode(state, forKey: .state)
        case let .alertRaised(at, alert):
            try c.encode("AlertRaised", forKey: ._tag)
            try c.encode(at, forKey: .at)
            try c.encode(alert, forKey: .alert)
        case let .alertCleared(at, alert):
            try c.encode("AlertCleared", forKey: ._tag)
            try c.encode(at, forKey: .at)
            try c.encode(alert, forKey: .alert)
        }
    }
}

enum ClipKind: String, Codable, Sendable { case text, link, image, file, folder }

/// One copy on the Mac, as the gateway's history records it (`MacClip` in clips.ts).
struct MacClip: Codable, Equatable, Sendable {
    let id: String
    let kind: ClipKind
    let at: Int64
    @Nullable var source: String?
    @Nullable var text: String?
    var truncated: Bool
    @Nullable var name: String?
    @Nullable var mime: String?
    var bytes: Int
    @Nullable var files: Int?
    @Nullable var thumb: String?
    /// File name inside `clips/` holding the bytes (images, long text).
    @Nullable var stored: String?
    /// Absolute path of a copied file or folder, materialized on first download.
    @Nullable var origin: String?
    var pushed: Bool?

    init(
        id: String, kind: ClipKind, at: Int64, source: String?, text: String? = nil, truncated: Bool = false,
        name: String? = nil, mime: String? = nil, bytes: Int = 0, files: Int? = nil, thumb: String? = nil,
        stored: String? = nil, origin: String? = nil, pushed: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.at = at
        self.source = source
        self.text = text
        self.truncated = truncated
        self.name = name
        self.mime = mime
        self.bytes = bytes
        self.files = files
        self.thumb = thumb
        self.stored = stored
        self.origin = origin
        self.pushed = pushed
    }
}

struct ClipPolicy: Codable, Equatable, Sendable {
    let enabled: Bool
    let keepDays: Int
}

enum QueryResult: Equatable, Sendable {
    case history([WireSeries])
    case apps(WireApps)
    case clipboard(String?)
    case setGuard(GuardSettings)
    case clipMaterialize(stored: String, bytes: Int, files: Int?)
    case clipPut(placed: Int)
    case fsThumbs([WireThumb])
    case fsOpen
}

struct WireThumb: Codable, Equatable, Sendable {
    let path: String
    @Nullable var jpeg: String?
}

extension QueryResult: Encodable {
    private enum Keys: String, CodingKey { case _tag, result, series, text, settings, stored, bytes, files, placed, thumbs }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .history(series):
            try c.encode("History", forKey: ._tag)
            var result = c.nestedContainer(keyedBy: Keys.self, forKey: .result)
            try result.encode(series, forKey: .series)
        case let .apps(apps):
            try c.encode("Apps", forKey: ._tag)
            try c.encode(apps, forKey: .result)
        case let .clipboard(text):
            try c.encode("Clipboard", forKey: ._tag)
            try c.encode(Nullable(wrappedValue: text), forKey: .text)
        case let .setGuard(settings):
            try c.encode("SetGuard", forKey: ._tag)
            try c.encode(settings, forKey: .settings)
        case let .clipMaterialize(stored, bytes, files):
            try c.encode("ClipMaterialize", forKey: ._tag)
            try c.encode(stored, forKey: .stored)
            try c.encode(bytes, forKey: .bytes)
            try c.encode(Nullable(wrappedValue: files), forKey: .files)
        case let .clipPut(placed):
            try c.encode("ClipPut", forKey: ._tag)
            try c.encode(placed, forKey: .placed)
        case let .fsThumbs(thumbs):
            try c.encode("FsThumbs", forKey: ._tag)
            try c.encode(thumbs, forKey: .thumbs)
        case .fsOpen:
            try c.encode("FsOpen", forKey: ._tag)
        }
    }
}

enum AdminOp: Equatable, Sendable {
    case createPairing
    case listDevices
    case revokeDevice(String)
    case setScopes(deviceId: String, scopes: [String])
    case resolvePairPrompt(id: String, allow: Bool)
    case fsDevices
    case fsRoots(device: String)
    case fsList(device: String, path: String, offset: Int)
    case fsThumbs(device: String, paths: [String])
    case fsPull(device: String, paths: [String])
    case fsRecent(device: String, kind: RecentKind, offset: Int)
    case clipsFrom(device: String)
}

/// What a device page lists newest first (`FsRecentKind` in fs.ts).
enum RecentKind: String, Codable, CaseIterable, Sendable { case photos, screenshots, downloads, documents }

extension AdminOp: Encodable {
    private enum Keys: String, CodingKey { case _tag, deviceId, scopes, id, allow, device, path, paths, offset, kind }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .createPairing: try c.encode("CreatePairing", forKey: ._tag)
        case .listDevices: try c.encode("ListDevices", forKey: ._tag)
        case let .revokeDevice(id):
            try c.encode("RevokeDevice", forKey: ._tag)
            try c.encode(id, forKey: .deviceId)
        case let .setScopes(id, scopes):
            try c.encode("SetScopes", forKey: ._tag)
            try c.encode(id, forKey: .deviceId)
            try c.encode(scopes, forKey: .scopes)
        case let .resolvePairPrompt(id, allow):
            try c.encode("ResolvePairPrompt", forKey: ._tag)
            try c.encode(id, forKey: .id)
            try c.encode(allow, forKey: .allow)
        case .fsDevices:
            try c.encode("FsDevices", forKey: ._tag)
        case let .fsRoots(device):
            try c.encode("FsRoots", forKey: ._tag)
            try c.encode(device, forKey: .device)
        case let .fsList(device, path, offset):
            try c.encode("FsList", forKey: ._tag)
            try c.encode(device, forKey: .device)
            try c.encode(path, forKey: .path)
            try c.encode(offset, forKey: .offset)
        case let .fsThumbs(device, paths):
            try c.encode("FsThumbs", forKey: ._tag)
            try c.encode(device, forKey: .device)
            try c.encode(paths, forKey: .paths)
        case let .fsPull(device, paths):
            try c.encode("FsPull", forKey: ._tag)
            try c.encode(device, forKey: .device)
            try c.encode(paths, forKey: .paths)
        case let .fsRecent(device, kind, offset):
            try c.encode("FsRecent", forKey: ._tag)
            try c.encode(device, forKey: .device)
            try c.encode(kind, forKey: .kind)
            try c.encode(offset, forKey: .offset)
        case let .clipsFrom(device):
            try c.encode("ClipsFrom", forKey: ._tag)
            try c.encode(device, forKey: .device)
        }
    }
}

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(value): try c.encode(value)
        case let .number(value): try c.encode(value)
        case let .bool(value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
}

enum FromApp: Equatable, Sendable {
    case hello(mac: WireMac, keepAwake: WireKeepAwake)
    case sample(WireSample)
    case processes(WireProcesses)
    case guardState(WireGuardState)
    case audio(WireAudio)
    case receipt(WireReceipt)
    case event(WireEvent)
    case result(id: String, ok: QueryResult?, error: String?)
    case admin(id: String, op: AdminOp)
    case log(level: String, kind: String, data: [String: JSONValue])
    case clip(MacClip)
    case clipPolicy(ClipPolicy)
    case clipClear
    case dropSend(to: [String], files: [MacDropFile])
    case dropDecision(id: String, accept: Bool)
    case dropCancel(id: String)
    case dropPause(id: String, paused: Bool)
    case dropPolicy(DropPolicy)
    case fsPolicy(access: String)
    case terminalEnd(id: String?, deviceId: String?)
}

extension FromApp: Encodable {
    private enum Keys: String, CodingKey { case t, v, mac, keepAwake, data, receipt, event, id, ok, error, op, level, kind, clip, policy, to, files, accept, paused, access, deviceId }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .hello(mac, keepAwake):
            try c.encode("hello", forKey: .t)
            try c.encode(1, forKey: .v)
            try c.encode(mac, forKey: .mac)
            try c.encode(keepAwake, forKey: .keepAwake)
        case let .sample(sample):
            try c.encode("sample", forKey: .t)
            try c.encode(sample, forKey: .data)
        case let .processes(snapshot):
            try c.encode("processes", forKey: .t)
            try c.encode(snapshot, forKey: .data)
        case let .guardState(state):
            try c.encode("guard", forKey: .t)
            try c.encode(state, forKey: .data)
        case let .audio(state):
            try c.encode("audio", forKey: .t)
            try c.encode(state, forKey: .data)
        case let .receipt(receipt):
            try c.encode("receipt", forKey: .t)
            try c.encode(receipt, forKey: .receipt)
        case let .event(event):
            try c.encode("event", forKey: .t)
            try c.encode(event, forKey: .event)
        case let .result(id, ok, error):
            try c.encode("result", forKey: .t)
            try c.encode(id, forKey: .id)
            if let ok { try c.encode(ok, forKey: .ok) } else { try c.encodeNil(forKey: .ok) }
            try c.encode(Nullable(wrappedValue: error), forKey: .error)
        case let .admin(id, op):
            try c.encode("admin", forKey: .t)
            try c.encode(id, forKey: .id)
            try c.encode(op, forKey: .op)
        case let .log(level, kind, data):
            try c.encode("log", forKey: .t)
            try c.encode(level, forKey: .level)
            try c.encode(kind, forKey: .kind)
            try c.encode(data, forKey: .data)
        case let .clip(clip):
            try c.encode("clip", forKey: .t)
            try c.encode(clip, forKey: .clip)
        case let .clipPolicy(policy):
            try c.encode("clipPolicy", forKey: .t)
            try c.encode(policy, forKey: .policy)
        case .clipClear:
            try c.encode("clipClear", forKey: .t)
        case let .dropSend(to, files):
            try c.encode("dropSend", forKey: .t)
            try c.encode(to, forKey: .to)
            try c.encode(files, forKey: .files)
        case let .dropDecision(id, accept):
            try c.encode("dropDecision", forKey: .t)
            try c.encode(id, forKey: .id)
            try c.encode(accept, forKey: .accept)
        case let .dropCancel(id):
            try c.encode("dropCancel", forKey: .t)
            try c.encode(id, forKey: .id)
        case let .dropPause(id, paused):
            try c.encode("dropPause", forKey: .t)
            try c.encode(id, forKey: .id)
            try c.encode(paused, forKey: .paused)
        case let .dropPolicy(policy):
            try c.encode("dropPolicy", forKey: .t)
            try c.encode(policy, forKey: .policy)
        case let .fsPolicy(access):
            try c.encode("fsPolicy", forKey: .t)
            try c.encode(access, forKey: .access)
        case let .terminalEnd(id, deviceId):
            try c.encode("terminalEnd", forKey: .t)
            try c.encode(Nullable(wrappedValue: id), forKey: .id)
            try c.encode(Nullable(wrappedValue: deviceId), forKey: .deviceId)
        }
    }
}
