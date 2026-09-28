import Foundation

/// Build channel, baked into Info.plist (`VitalsChannel`) by `build.sh`.
/// Defaults to `.stable` when absent (e.g. `swift run`). Channels install side
/// by side because their bundle ids differ.
enum Channel: String {
    case stable
    case nightly
    case dev

    static let current: Channel = {
        let raw = Bundle.main.infoDictionary?["VitalsChannel"] as? String
        return raw.flatMap(Channel.init(rawValue:)) ?? .stable
    }()

    /// Matches `CFBundleName` and the `.app` on disk. `FanHelperRetirement` and
    /// `Updater.bundleInImage` derive paths from this, so it must match `build.sh`.
    var displayName: String {
        switch self {
        case .stable:  return "Vitals"
        case .nightly: return "Vitals Nightly"
        case .dev:     return "Vitals Dev"
        }
    }

    /// nil on Stable.
    var badge: String? {
        switch self {
        case .stable:  return nil
        case .nightly: return "NIGHTLY"
        case .dev:     return "DEV"
        }
    }

    /// The published DMG asset. nil for Dev, which never publishes.
    var assetName: String? {
        switch self {
        case .stable:  return "Vitals.dmg"
        case .nightly: return "Vitals-Nightly.dmg"
        case .dev:     return nil
        }
    }

    /// Hidden data-home directory name under `~/`.
    var dataDirSuffix: String {
        switch self {
        case .stable:  return ".vitals"
        case .nightly: return ".vitals-nightly"
        case .dev:     return ".vitals-dev"
        }
    }

    var isPrerelease: Bool { self == .nightly }

    var updatesEnabled: Bool { self != .dev }

    /// branch@sha, baked in for Nightly and Dev. nil on Stable.
    static var buildInfo: String? {
        Bundle.main.infoDictionary?["VitalsBuildInfo"] as? String
    }
}
