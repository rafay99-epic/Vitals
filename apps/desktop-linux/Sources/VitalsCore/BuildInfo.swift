import Foundation

/// Build-time identity. The version is injected by `build.sh` via the
/// `VITALS_VERSION` environment variable (`0.<commit-count>`, matching the
/// macOS app); falls back to "dev" for plain `swift run`.
public enum BuildInfo {
    public static let appID = "com.rafay99.Vitals"
    public static let displayName = "Vitals"
    public static var version: String {
        ProcessInfo.processInfo.environment["VITALS_VERSION"] ?? "dev"
    }
}
