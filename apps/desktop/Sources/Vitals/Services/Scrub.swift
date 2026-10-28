import Foundation
import SystemConfiguration

/// What never leaves the Mac for Sentry: the user's name and home folder, the Mac's name, links,
/// email and IP addresses, tailnet names, folder paths and file names. Mirrors the phone app's
/// `scrub.ts`. Order matters: whole links go before the paths inside them.
enum Scrub {
    private static let fileTypes = "png|jpe?g|heic|heif|gif|webp|svg|mp4|mov|m4v|mkv|mp3|m4a|wav|aac|pdf|docx?|xlsx?|pptx?|key|pages|numbers|txt|md|rtf|csv|json|xml|zip|tar|gz|dmg|pkg|apk|ipa|app|plist|sqlite3?|log"

    private static let rules: [(NSRegularExpression, String)] = [
        (#"\b[a-z][a-z0-9+.-]*://[^\s"'<>)]+"#, "<url>"),
        (#"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"#, "<email>"),
        (#"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#, "<ip>"),
        (#"\b[\w-]+(?:\.[\w-]+)*\.ts\.net\b"#, "<host>"),
        (#"\b[\w-]+\.local\b"#, "<host>"),
        // IPv6: four or more groups, or a "fe80::" form, so a time (11:10:46) and std::x stay.
        (#"(?:\b[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b(?:%\w+)?|\b[0-9a-f]{1,4}::(?:[0-9a-f]{1,4}:?){0,6}\b(?:%\w+)?"#, "<ip>"),
        // macOS names a file in “curly quotes” ("The file “Taxes” couldn’t be opened").
        (#"“[^”\n]{1,200}”"#, "“<name>”"),
        (#"(?:~|\b[A-Za-z]:)?(?:/[^\s/"'<>:]+){2,}/?"#, "<path>"),
        (#"[^\s/\\"'<>]+\.(?:\#(fileTypes))\b"#, "<file>")
    ].compactMap { pattern, label in
        // Fixed literals: a typo drops its rule, and ScrubTests fails.
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { ($0, label) }
    }

    /// Names that identify the owner, replaced before the patterns run. Longest first, so the
    /// home folder goes before the user name inside it.
    private static let identities: [(String, String)] = [
        (NSHomeDirectory(), "~"),
        // The Mac's name as set in Sharing; `Host.current()` can stall on DNS.
        ((SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "", "<mac>"),
        (NSFullUserName(), "<user>"),
        (NSUserName(), "<user>")
    ].filter { $0.0.count >= 3 }

    /// Only the owner's names (home folder, Mac, user), for paths that should stay readable.
    static func home(_ text: String, identities: [(String, String)] = identities) -> String {
        identities.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    static func text(_ text: String, identities: [(String, String)] = identities) -> String {
        var out = home(text, identities: identities)
        for (regex, label) in rules {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: label)
        }
        return out
    }
}
