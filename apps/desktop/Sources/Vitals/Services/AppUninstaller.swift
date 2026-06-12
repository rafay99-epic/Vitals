import Foundation
import AppKit

/// Removes an app and its leftovers. Everything goes to the Trash — never a
/// hard delete — so any mistake is recoverable from the Finder.
enum AppUninstaller {
    struct Outcome {
        var trashed: [URL] = []
        var failures: [(url: URL, reason: String)] = []
        var freedBytes: UInt64 = 0
    }

    static func runningApplication(bundleID: String?) -> NSRunningApplication? {
        guard let bundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }
    }

    /// Trashes the app bundle and the given leftovers. Launch agents are
    /// booted out of launchd first so nothing respawns mid-removal.
    static func uninstall(app: InstalledApp, leftovers: [Leftover]) -> Outcome {
        var outcome = Outcome()

        for leftover in leftovers where leftover.category == .launchAgents {
            bootout(agentPlist: leftover.id)
        }

        var sizes: [URL: UInt64] = [app.id: app.sizeBytes ?? 0]
        for leftover in leftovers { sizes[leftover.id] = leftover.sizeBytes }

        for url in [app.id] + leftovers.map(\.id) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                outcome.trashed.append(url)
                outcome.freedBytes += sizes[url] ?? 0
            } catch {
                outcome.failures.append((url, error.localizedDescription))
            }
        }
        return outcome
    }

    /// Best-effort: tell launchd to stop a user launch agent before its plist
    /// is trashed. Failure is fine — the agent simply won't load next login.
    private static func bootout(agentPlist: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", agentPlist.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}
