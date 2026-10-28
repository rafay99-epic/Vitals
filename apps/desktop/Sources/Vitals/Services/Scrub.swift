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

    static func text(_ text: String, identities: [(String, String)] = identities) -> String {
        var out = text
        for (name, label) in identities { out = out.replacingOccurrences(of: name, with: label) }
        for (regex, label) in rules {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: label)
        }
        return out
    }
}
