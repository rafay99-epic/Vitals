import Foundation

/// Which build channel this app is. Baked into Info.plist (`VitalsChannel`) by
/// `build.sh`; defaults to `.stable` when the key is absent (e.g. a plain
/// `swift run`). Two channels install side by side because their bundle ids
/// differ — Stable is your daily driver (auto-updates from GitHub releases),
/// Dev is whatever branch you built (separate data, distinct icon, no updater).
enum Channel: String {
    case stable
    case dev

    static let current: Channel = {
        let raw = Bundle.main.infoDictionary?["VitalsChannel"] as? String
        return raw.flatMap(Channel.init(rawValue:)) ?? .stable
    }()

    var isDev: Bool { self == .dev }

    /// Human-facing app name — matches `CFBundleName`.
    var displayName: String {
        self == .dev ? "Vitals Dev" : "Vitals"
    }

    /// Short corner-of-the-UI tag, nil on Stable.
    var badge: String? {
        self == .dev ? "DEV" : nil
    }

    /// Extra build detail (branch@sha), baked in for Dev so the About screen can
    /// show exactly what's running. nil on Stable.
    static var buildInfo: String? {
        Bundle.main.infoDictionary?["VitalsBuildInfo"] as? String
    }
}
