import Foundation

@propertyWrapper
struct Nullable<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try container.decode(Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(wrappedValue) } else { try container.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    func decode<Value>(_ type: Nullable<Value>.Type, forKey key: Key) throws -> Nullable<Value> {
        try decodeIfPresent(type, forKey: key) ?? Nullable(wrappedValue: nil)
    }
}

struct ProcessRef: Codable, Equatable, Hashable, Sendable {
    let pid: Int32
    let startTimeMs: Int64
}

struct AppRef: Codable, Equatable, Sendable {
    let pid: Int32
    @Nullable var bundleId: String?
}

struct ProcessAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case throttle, unthrottle, pause, resume, terminate, kill }
    let target: ProcessRef
    let action: Kind
}

enum RemoteCommand: Equatable, Sendable {
    case keepAwake(until: Int64?, display: Bool, whileProcess: ProcessRef?)
    case allowSleep
    case displayOff
    case lock
    case sleep(grace: Int)
    case restart(grace: Int)
    case shutDown(grace: Int)
    case logOut(grace: Int)
    case processes([ProcessAction])
    case quitApp(AppRef)
    case hideApp(AppRef)
    case forceQuitApp(AppRef)
    case launchApp(bundleId: String)
    case stopEmulator(kind: String, id: String)
    case setVolume(Double)
    case setMuted(Bool)
    case clipboardSet(String)
    case openURL(String)
    case locate
    case calmDown(alertId: String?)
    case undoCalm

    var tag: String {
        switch self {
        case .keepAwake: return "KeepAwake"
        case .allowSleep: return "AllowSleep"
        case .displayOff: return "DisplayOff"
        case .lock: return "Lock"
        case .sleep: return "Sleep"
        case .restart: return "Restart"
        case .shutDown: return "ShutDown"
        case .logOut: return "LogOut"
        case .processes: return "Processes"
        case .quitApp: return "QuitApp"
        case .hideApp: return "HideApp"
        case .forceQuitApp: return "ForceQuitApp"
        case .launchApp: return "LaunchApp"
        case .stopEmulator: return "StopEmulator"
        case .setVolume: return "SetVolume"
        case .setMuted: return "SetMuted"
        case .clipboardSet: return "ClipboardSet"
        case .openURL: return "OpenUrl"
        case .locate: return "Locate"
        case .calmDown: return "CalmDown"
        case .undoCalm: return "UndoCalm"
        }
    }

    var graceSeconds: Int {
        switch self {
        case let .sleep(grace), let .restart(grace), let .shutDown(grace), let .logOut(grace): return grace
        default: return 0
        }
    }
}

extension RemoteCommand: Decodable {
    private enum Keys: String, CodingKey {
        case _tag, until, display, whileProcess, graceSeconds, actions, app, bundleId, kind, id, level, muted, text, url, alertId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let tag = try c.decode(String.self, forKey: ._tag)
        switch tag {
        case "KeepAwake":
            self = .keepAwake(
                until: try c.decodeIfPresent(Int64.self, forKey: .until),
                display: try c.decode(Bool.self, forKey: .display),
                whileProcess: try c.decodeIfPresent(ProcessRef.self, forKey: .whileProcess)
            )
        case "AllowSleep": self = .allowSleep
        case "DisplayOff": self = .displayOff
        case "Lock": self = .lock
        case "Sleep": self = .sleep(grace: try c.decode(Int.self, forKey: .graceSeconds))
        case "Restart": self = .restart(grace: try c.decode(Int.self, forKey: .graceSeconds))
        case "ShutDown": self = .shutDown(grace: try c.decode(Int.self, forKey: .graceSeconds))
        case "LogOut": self = .logOut(grace: try c.decode(Int.self, forKey: .graceSeconds))
        case "Processes": self = .processes(try c.decode([ProcessAction].self, forKey: .actions))
        case "QuitApp": self = .quitApp(try c.decode(AppRef.self, forKey: .app))
        case "HideApp": self = .hideApp(try c.decode(AppRef.self, forKey: .app))
        case "ForceQuitApp": self = .forceQuitApp(try c.decode(AppRef.self, forKey: .app))
        case "LaunchApp": self = .launchApp(bundleId: try c.decode(String.self, forKey: .bundleId))
        case "StopEmulator":
            self = .stopEmulator(kind: try c.decode(String.self, forKey: .kind), id: try c.decode(String.self, forKey: .id))
        case "SetVolume": self = .setVolume(try c.decode(Double.self, forKey: .level))
        case "SetMuted": self = .setMuted(try c.decode(Bool.self, forKey: .muted))
        case "ClipboardSet": self = .clipboardSet(try c.decode(String.self, forKey: .text))
        case "OpenUrl": self = .openURL(try c.decode(String.self, forKey: .url))
        case "Locate": self = .locate
        case "CalmDown": self = .calmDown(alertId: try c.decodeIfPresent(String.self, forKey: .alertId))
        case "UndoCalm": self = .undoCalm
        default:
            throw DecodingError.dataCorruptedError(forKey: ._tag, in: c, debugDescription: "unknown command \(tag)")
        }
    }
}

struct HistoryInput: Codable, Equatable, Sendable {
    let series: [String]
    let from: Int64
    let to: Int64
    let points: Int
}

struct GuardRule: Codable, Equatable, Sendable {
    let kind: String
    let enabled: Bool
    let threshold: Double
    let holdSeconds: Int
}

struct GuardSettings: Codable, Equatable, Sendable {
    let enabled: Bool
    let cooldownSeconds: Int
    let rules: [GuardRule]
}

/// One clip the gateway already resolved for the Mac to place (`ClipPlacement` in clips.ts).
struct ClipPlacement: Codable, Equatable, Sendable {
    let kind: ClipKind
    @Nullable var stored: String?
    @Nullable var text: String?
    @Nullable var name: String?
    @Nullable var mime: String?
}

enum ClipDestination: String, Codable, Sendable { case clipboard, downloads }

enum BridgeQuery: Equatable, Sendable {
    case history(HistoryInput)
    case apps
    case clipboard
    case setGuard(GuardSettings)
    /// Clone a copied file, or zip a copied folder, into `clips/`.
    case clipMaterialize(id: String, kind: ClipKind, origin: String)
    /// Put phone clips on the Mac clipboard or into Downloads.
    case clipPut(items: [ClipPlacement], to: ClipDestination, folder: String?, deviceName: String)
    case fsThumbs(paths: [String], pixels: Int)
    case fsTrash(paths: [String], deviceName: String)
    case fsOpen(path: String)
}

extension BridgeQuery: Decodable {
    private enum Keys: String, CodingKey { case _tag, input, settings, id, kind, origin, items, to, folder, deviceName, paths, pixels, path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: ._tag) {
        case "History": self = .history(try c.decode(HistoryInput.self, forKey: .input))
        case "Apps": self = .apps
        case "Clipboard": self = .clipboard
        case "SetGuard": self = .setGuard(try c.decode(GuardSettings.self, forKey: .settings))
        case "ClipMaterialize":
            self = .clipMaterialize(
                id: try c.decode(String.self, forKey: .id),
                kind: try c.decode(ClipKind.self, forKey: .kind),
                origin: try c.decode(String.self, forKey: .origin)
            )
        case "ClipPut":
            self = .clipPut(
                items: try c.decode([ClipPlacement].self, forKey: .items),
                to: try c.decode(ClipDestination.self, forKey: .to),
                folder: try c.decodeIfPresent(String.self, forKey: .folder),
                deviceName: try c.decode(String.self, forKey: .deviceName)
            )
        case "FsThumbs":
            self = .fsThumbs(paths: try c.decode([String].self, forKey: .paths), pixels: try c.decode(Int.self, forKey: .pixels))
        case "FsTrash":
            self = .fsTrash(paths: try c.decode([String].self, forKey: .paths), deviceName: try c.decode(String.self, forKey: .deviceName))
        case "FsOpen":
            self = .fsOpen(path: try c.decode(String.self, forKey: .path))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: ._tag, in: c, debugDescription: "unknown query \(other)")
        }
    }
}

struct GatewayStatus: Codable, Equatable, Sendable {
    enum Serve: String, Codable, Sendable { case off, starting, serving, degraded }

    /// The gateway's Wi-Fi listener: what Bonjour advertises.
    struct Lan: Codable, Equatable, Sendable {
        let port: Int
        /// The Mac's base64url X25519 public key; phones pin it.
        let key: String
        /// The gateway reached its own Wi-Fi address. False while macOS's firewall or
        /// Local Network prompt is unanswered or denied. nil from an older gateway.
        let reachable: Bool?
    }

    let serve: Serve
    @Nullable var url: String?
    @Nullable var detail: String?
    @Nullable var ownerLogin: String?
    let clients: Int
    @Nullable var lan: Lan?
    /// Optional so an older gateway that omits it still decodes.
    var setup: TailscaleSetup?
}

/// The next thing the user has to do for away access, as the gateway sees it.
struct TailscaleSetup: Codable, Equatable, Sendable {
    enum Step: String, Codable, Sendable {
        case install, start, signin, magicdns, https, ready, external

        /// Unknown steps from a newer gateway read as `external` (shows the detail) instead of failing the whole status.
        init(from decoder: Decoder) throws {
            self = Step(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .external
        }

        /// The "step N of 4" position. nil when Tailscale is managed elsewhere.
        var number: Int? {
            switch self {
            case .install: return 1
            case .start, .signin: return 2
            case .magicdns, .https: return 3
            case .ready: return 4
            case .external: return nil
            }
        }
    }

    let step: Step
    /// A page to open for this step, such as Tailscale's one-time HTTPS consent link.
    @Nullable var url: String?
}

struct DeviceInfo: Codable, Equatable, Sendable {
    let name: String
    let platform: String
    let model: String
    let appVersion: String
}

/// A phone on the Wi-Fi asking to pair. The user allows or denies it on the Mac.
struct PairPrompt: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let device: DeviceInfo
    /// Four digits the phone also shows, so the user can match them.
    let code: String
    let address: String
    let expiresAt: Int64

    var expiry: Date { Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000) }
}

struct RemoteDevice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let platform: String
    let model: String
    let appVersion: String
    var scopes: [String]
    let createdAt: Int64
    @Nullable var lastSeenAt: Int64?
    @Nullable var revokedAt: Int64?
    let connected: Bool
}

enum AdminResult: Equatable, Sendable {
    case createPairing(code: String, url: String?, expiresAt: Int64)
    case listDevices([RemoteDevice])
    case revokeDevice
    case setScopes
    case resolvePairPrompt
}

extension AdminResult: Decodable {
    private enum Keys: String, CodingKey { case _tag, code, url, expiresAt, devices }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: ._tag) {
        case "CreatePairing":
            self = .createPairing(
                code: try c.decode(String.self, forKey: .code),
                url: try c.decodeIfPresent(String.self, forKey: .url),
                expiresAt: try c.decode(Int64.self, forKey: .expiresAt)
            )
        case "ListDevices": self = .listDevices(try c.decode([RemoteDevice].self, forKey: .devices))
        case "RevokeDevice": self = .revokeDevice
        case "SetScopes": self = .setScopes
        case "ResolvePairPrompt": self = .resolvePairPrompt
        case let other:
            throw DecodingError.dataCorruptedError(forKey: ._tag, in: c, debugDescription: "unknown admin result \(other)")
        }
    }
}

struct NeedsMessage: Decodable, Equatable, Sendable {
    struct Processes: Decodable, Equatable, Sendable {
        let sortBy: String
        let limit: Int
    }
    let topics: [String]
    let intervalMs: Int
    let processes: Processes?
    let guardState: Bool

    private enum Keys: String, CodingKey { case topics, intervalMs, processes, guardState = "guard" }

    init(topics: [String], intervalMs: Int, processes: Processes?, guardState: Bool) {
        self.topics = topics
        self.intervalMs = intervalMs
        self.processes = processes
        self.guardState = guardState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        topics = try c.decode([String].self, forKey: .topics)
        intervalMs = try c.decode(Int.self, forKey: .intervalMs)
        processes = try c.decodeIfPresent(Processes.self, forKey: .processes)
        guardState = try c.decode(Bool.self, forKey: .guardState)
    }

    static let none = NeedsMessage(topics: [], intervalMs: 2000, processes: nil, guardState: false)
}

enum ToApp: Equatable, Sendable {
    case hello(version: Int)
    case need(NeedsMessage)
    case command(id: String, deviceId: String, deviceName: String, command: RemoteCommand)
    case cancel(id: String)
    case query(id: String, query: BridgeQuery)
    case adminResult(id: String, result: AdminResult?, error: String?)
    case status(GatewayStatus)
    case pairPrompt(PairPrompt)
    case pairPromptEnded(id: String)
    case clipStats(ClipStats)
    case drop(Drop)
    case dropRemoved(id: String)
    case dropReceived(id: String, from: DropPeer, files: [ReceivedDropFile], dest: String?)
    case terminals([MacTerminal])
}

struct MacTerminal: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let deviceId: String
    let deviceName: String
    let startedAt: Int64
    let attached: Int
}

/// What the gateway's clip history holds right now, for Settings.
struct ClipStats: Codable, Equatable, Sendable {
    let clips: Int
    let pinned: Int
    let bytes: Int
}

extension ToApp: Decodable {
    private enum Keys: String, CodingKey { case t, v, id, deviceId, deviceName, command, q, ok, error, status, prompt, stats, drop, from, files, dest, sessions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .t) {
        case "hello": self = .hello(version: try c.decode(Int.self, forKey: .v))
        case "need": self = .need(try NeedsMessage(from: decoder))
        case "cmd":
            self = .command(
                id: try c.decode(String.self, forKey: .id),
                deviceId: try c.decode(String.self, forKey: .deviceId),
                deviceName: try c.decode(String.self, forKey: .deviceName),
                command: try c.decode(RemoteCommand.self, forKey: .command)
            )
        case "cancel": self = .cancel(id: try c.decode(String.self, forKey: .id))
        case "query": self = .query(id: try c.decode(String.self, forKey: .id), query: try c.decode(BridgeQuery.self, forKey: .q))
        case "adminResult":
            self = .adminResult(
                id: try c.decode(String.self, forKey: .id),
                result: try c.decodeIfPresent(AdminResult.self, forKey: .ok),
                error: try c.decodeIfPresent(String.self, forKey: .error)
            )
        case "status": self = .status(try c.decode(GatewayStatus.self, forKey: .status))
        case "pairPrompt": self = .pairPrompt(try c.decode(PairPrompt.self, forKey: .prompt))
        case "pairPromptEnded": self = .pairPromptEnded(id: try c.decode(String.self, forKey: .id))
        case "clipStats": self = .clipStats(try c.decode(ClipStats.self, forKey: .stats))
        case "drop": self = .drop(try c.decode(Drop.self, forKey: .drop))
        case "dropRemoved": self = .dropRemoved(id: try c.decode(String.self, forKey: .id))
        case "dropReceived":
            self = .dropReceived(
                id: try c.decode(String.self, forKey: .id),
                from: try c.decode(DropPeer.self, forKey: .from),
                files: try c.decode([ReceivedDropFile].self, forKey: .files),
                dest: try c.decodeIfPresent(String.self, forKey: .dest)
            )
        case "terminals": self = .terminals(try c.decode([MacTerminal].self, forKey: .sessions))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown message \(other)")
        }
    }
}
