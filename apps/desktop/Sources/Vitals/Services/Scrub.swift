import Foundation
import SystemConfiguration

enum Scrub {
    private static let fileTypes = "png|jpe?g|heic|heif|gif|webp|svg|mp4|mov|m4v|mkv|mp3|m4a|wav|aac|pdf|docx?|xlsx?|pptx?|key|pages|numbers|txt|md|rtf|csv|json|xml|zip|tar|gz|dmg|pkg|apk|ipa|app|plist|sqlite3?|log"

    private static let rules: [(NSRegularExpression, String)] = [
        (#"\b[a-z][a-z0-9+.-]*://[^\s"'<>)]+"#, "<url>"),
        (#"[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,}\b"#, "<email>"),
        (#"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#, "<ip>"),
        (#"\b[\w-]+(?:\.[\w-]+)*\.ts\.net\b"#, "<host>"),
        (#"\b[\w-]+\.local\b"#, "<host>"),
        (#"(?:\b[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b(?:%\w+)?|\b[0-9a-f]{1,4}::(?:[0-9a-f]{1,4}:?){0,6}\b(?:%\w+)?"#, "<ip>"),
        (#"“[^”\n]{1,200}”"#, "“<name>”"),
        (#"(?:~|\b[A-Za-z]:)?(?:/[^\s/"'<>:]+){2,}/?"#, "<path>"),
        (#"[^\s/\\"'<>]+\.(?:\#(fileTypes))\b(?!\.\w)"#, "<file>")
    ].compactMap { pattern, label in
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { ($0, label) }
    }

    private static let identities: [(String, String)] = [
        (NSHomeDirectory(), "~"),
        ((SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "", "<mac>"),
        (NSFullUserName(), "<user>"),
        (NSUserName(), "<user>")
    ].filter { $0.0.count >= 3 }

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
