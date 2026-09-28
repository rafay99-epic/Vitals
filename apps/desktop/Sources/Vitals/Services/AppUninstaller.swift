import Foundation
import AppKit

/// Removes an app and everything it leaves behind. User-domain files go to the
/// Trash (recoverable); system-domain files are removed permanently as root
/// through `PrivilegedShell` after explicit confirmation. Homebrew casks are
/// handed to `brew uninstall`, and the app's preferences domain is cleared.
enum AppUninstaller {
    struct Outcome {
        var trashed: [URL] = []
        var failures: [(url: URL, reason: String)] = []
        var freedBytes: UInt64 = 0
        var systemRemoved = 0
        var usedAdmin = false
        /// The user dismissed the admin prompt, so system-domain files (and any
        /// root-owned bundle) were left in place. The summary must say so.
        var adminCancelled = false
        var caskUninstalled = 0
        var errorMessage: String?
        /// Bundles the user couldn't trash. The caller retries them through the
        /// admin removal path.
        var failedBundles: [URL] = []
    }

    static func runningApplication(bundleID: String?) -> NSRunningApplication? {
        guard let bundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }
    }

    /// Whether the user can't trash an app bundle because it's root-owned (pkg
    /// install) or its parent isn't writable. Such bundles go through the admin
    /// path instead.
    static func bundleNeedsAdmin(_ url: URL) -> Bool {
        let fm = FileManager.default
        if let owner = try? fm.attributesOfItem(atPath: url.path)[.ownerAccountID] as? Int, owner == 0 {
            return true
        }
        return !fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    /// Trashes the app bundle (unless Homebrew already removed it) and the
    /// user-domain leftovers. System-domain leftovers are handled separately by
    /// `systemRemovalScript`. User launch agents are booted out of launchd
    /// first so nothing respawns mid-removal.
    static func uninstall(app: InstalledApp, leftovers: [Leftover], skipBundle: Bool) -> Outcome {
        var outcome = Outcome()
        let userLeftovers = leftovers.filter { !$0.requiresAdmin }

        for leftover in userLeftovers where leftover.category == .launchAgents {
            bootout(agentPlist: leftover.id)
        }

        var sizes: [URL: UInt64] = [app.id: app.sizeBytes ?? 0]
        for leftover in userLeftovers { sizes[leftover.id] = leftover.sizeBytes }

        // App Management can block the trash even when ownership looks fine, so
        // a failure falls back to the admin path instead of a hard error.
        if !skipBundle {
            do {
                try FileManager.default.trashItem(at: app.id, resultingItemURL: nil)
                outcome.trashed.append(app.id)
                outcome.freedBytes += sizes[app.id] ?? 0
            } catch {
                Log.notice(.uninstall, "bundle trash failed for \(app.id.lastPathComponent), will try admin path", error: error)
                outcome.failedBundles.append(app.id)
            }
        }
        for url in userLeftovers.map(\.id) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                outcome.trashed.append(url)
                outcome.freedBytes += sizes[url] ?? 0
            } catch {
                Log.notice(.uninstall, "couldn't trash leftover \(url.lastPathComponent)", error: error)
                outcome.failures.append((url, error.localizedDescription))
            }
        }
        return outcome
    }

    /// `defaults delete <bundle>`: clears the domain from cfprefsd so a reinstall
    /// starts clean. Runs as the user; no-op if the domain is absent.
    static func clearDefaults(bundleID: String?) {
        guard let bundleID, LeftoverScanner.isValidBundleID(bundleID) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.notice(.uninstall, "couldn't clear the preferences domain \(bundleID)", error: error)
            return
        }
        process.waitUntilExit()
    }

    /// Runs `brew uninstall --cask --zap <token>` as the user. `--zap` also
    /// removes the files the cask's `zap` stanza declares. The token is
    /// validated to brew's lowercase-alnum-hyphen shape.
    static func homebrewUninstall(cask: String) -> Bool {
        guard let brew = LeftoverScanner.brewExecutable(),
              cask.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["uninstall", "--cask", "--zap", cask]
        // Discard output: an unread Pipe fills at ~64 KB and hangs the child.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.notice(.uninstall, "couldn't launch brew to uninstall cask \(cask)", error: error)
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// A root `rm -rf` script for the given system-domain leftover paths. Every
    /// path is re-validated independently of how it was discovered: absolute,
    /// no `..`, never the bare root, never under `/System`, basename not
    /// `com.apple.*`, and confined to an allowlisted root. Failures are dropped,
    /// never executed. Nil if nothing remains.
    static func systemRemovalScript(for paths: [URL]) -> String? {
        let allowedRoots = ["/Library/", "/Users/Shared/", "/private/var/db/receipts/"]
        var lines = ["#!/bin/sh", "# Vitals app removal — exact validated paths only."]
        var any = false
        for url in paths {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("/"), path != "/", !path.contains(".."), !path.contains("'") else { continue }
            guard !path.hasPrefix("/System") else { continue }
            guard !url.lastPathComponent.hasPrefix("com.apple.") else { continue }
            // Plus the bundle itself under /Applications when it couldn't be
            // trashed: only ever an explicit ".app" the user confirmed.
            let underApplications = path.hasPrefix("/Applications/") && url.pathExtension == "app"
            guard underApplications || allowedRoots.contains(where: { path.hasPrefix($0) }) else { continue }
            lines.append("rm -rf '\(path)' 2>/dev/null || true")
            any = true
        }
        return any ? lines.joined(separator: "\n") : nil
    }

    /// Best-effort: stop a user launch agent before its plist is trashed. Failure
    /// is fine; the agent just won't load next login.
    private static func bootout(agentPlist: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", agentPlist.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}
