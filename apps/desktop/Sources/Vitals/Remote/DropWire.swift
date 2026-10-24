import Foundation

enum DropPeer: Equatable, Hashable, Sendable {
    case mac(name: String)
    case device(id: String, name: String)

    var name: String {
        switch self {
        case let .mac(name), let .device(_, name): return name
        }
    }

    var deviceId: String? {
        if case let .device(id, _) = self { return id }
        return nil
    }
}

extension DropPeer: Codable {
    private enum Keys: String, CodingKey { case _tag, name, deviceId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let name = try c.decode(String.self, forKey: .name)
        switch try c.decode(String.self, forKey: ._tag) {
        case "Mac": self = .mac(name: name)
        case "Device": self = .device(id: try c.decode(String.self, forKey: .deviceId), name: name)
        case let other: throw DecodingError.dataCorruptedError(forKey: ._tag, in: c, debugDescription: "unknown peer \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .mac(name):
            try c.encode("Mac", forKey: ._tag)
            try c.encode(name, forKey: .name)
        case let .device(id, name):
            try c.encode("Device", forKey: ._tag)
            try c.encode(id, forKey: .deviceId)
            try c.encode(name, forKey: .name)
        }
    }
}

enum DropState: String, Codable, Sendable, CaseIterable {
    case asking, waiting, running, paused, done, failed, cancelled, declined

    var isActive: Bool { self == .running || self == .paused }
    var isFinished: Bool { [.done, .failed, .cancelled, .declined].contains(self) }
}

enum DropRoute: String, Codable, Sendable {
    case lan, tailnet

    var label: String { self == .lan ? "Wi-Fi" : "Tailscale" }
}

struct DropFile: Codable, Equatable, Sendable {
    let id: String
    let name: String
    @Nullable var path: String?
    let size: Int
    @Nullable var mime: String?
    @Nullable var sha256: String?
    let done: Int
}

struct Drop: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let from: DropPeer
    let to: DropPeer
    let files: [DropFile]
    let bytes: Int
    let done: Int
    let state: DropState
    @Nullable var route: DropRoute?
    let createdAt: Int64
    let updatedAt: Int64
    @Nullable var error: String?

    var isOutgoing: Bool { if case .mac = from { return true } else { return false } }
    var phone: DropPeer { isOutgoing ? to : from }
    var fraction: Double { bytes > 0 ? min(1, Double(done) / Double(bytes)) : (state == .done ? 1 : 0) }
    var percent: Int { Int((fraction * 100).rounded(.down)) }
    var updated: Date { Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1000) }
}

struct DropPolicy: Codable, Equatable, Sendable {
    let autoAccept: Bool
    let askWeb: Bool
    let maxBytes: Int
}

struct MacDropFile: Codable, Equatable, Sendable {
    let name: String
    @Nullable var path: String?
    let size: Int
    @Nullable var mime: String?
    let origin: String
}

struct ReceivedDropFile: Codable, Equatable, Sendable {
    let stored: String
    let name: String
    @Nullable var path: String?
    let size: Int
}
