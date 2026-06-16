import Foundation

/// Mirrors the app's settings — every UserDefaults key Vitals owns — to a
/// readable JSON file at `~/.vitals/config/config.json`. This is the durable,
/// human-editable source of truth.
///
/// UserDefaults is fast but fragile: an app reinstall, or a Homebrew cask
/// upgrade that clears preferences, can wipe it — taking the user's whole setup
/// with it. The config file lives in the data home, which survives all of that,
/// so on launch `restore(into:)` pushes it back into UserDefaults *before*
/// anything reads them. A wipe becomes self-healing, and the file doubles as a
/// backup the user can read, edit, or copy between machines.
enum ConfigStore {
    static var fileURL: URL { DataHome.configFile }

    /// Keys whose stored value is JSON-encoded `Data`. They're expanded to
    /// readable nested JSON in the config file (and collapsed back on restore),
    /// so e.g. alert rules are legible rather than an opaque blob.
    private static let jsonDataKeys: Set<String> = ["alertRules"]

    /// Serializes `keys` from `defaults` to pretty, key-sorted JSON. Pure — no
    /// I/O — so the caller can compare it against the last write in memory and
    /// skip the disk entirely when nothing changed (`.sortedKeys` makes the bytes
    /// stable for that compare). Returns nil if there's nothing valid to encode.
    static func serialize(_ defaults: UserDefaults, keys: [String]) -> Data? {
        var dict: [String: Any] = [:]
        for key in keys {
            if jsonDataKeys.contains(key) {
                if let data = defaults.data(forKey: key),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    dict[key] = json
                }
            } else if let value = defaults.object(forKey: key) {
                dict[key] = value
            }
        }
        guard JSONSerialization.isValidJSONObject(dict) else { return nil }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    /// Writes serialized config bytes to `url` atomically.
    static func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.notice(.settings, "couldn't write settings config", error: error)
        }
    }

    /// Convenience: serialize and write in one step (used by tests).
    static func save(_ defaults: UserDefaults, keys: [String], to url: URL = fileURL) {
        guard let data = serialize(defaults, keys: keys) else { return }
        write(data, to: url)
    }

    /// If the config file exists, pushes its values back into `defaults`. Returns
    /// how many keys were restored (0 when the file is absent — a fresh install).
    @discardableResult
    static func restore(into defaults: UserDefaults, from url: URL = fileURL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        for (key, value) in dict {
            if jsonDataKeys.contains(key) {
                if let encoded = try? JSONSerialization.data(withJSONObject: value) {
                    defaults.set(encoded, forKey: key)
                }
            } else {
                defaults.set(value, forKey: key)
            }
        }
        return dict.count
    }
}
