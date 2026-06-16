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

    /// Reads `keys` from `defaults` and writes them as pretty JSON. Skips the
    /// write when the content is unchanged, so incidental republishes (window
    /// focus, etc.) don't churn the file.
    static func save(_ defaults: UserDefaults, keys: [String], to url: URL = fileURL) {
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
        guard JSONSerialization.isValidJSONObject(dict),
              let out = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        else { return }
        if let existing = try? Data(contentsOf: url), existing == out { return }  // nothing changed

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try out.write(to: url, options: .atomic)
        } catch {
            Log.notice(.settings, "couldn't write settings config", error: error)
        }
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
