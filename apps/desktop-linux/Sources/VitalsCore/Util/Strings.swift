import Foundation

extension StringProtocol {
    /// sysfs and proc files are line-oriented and almost always carry a trailing
    /// newline; trimming keeps the parsers from tripping over it.
    var trimmed: String { String(self).trimmingCharacters(in: .whitespacesAndNewlines) }
}
