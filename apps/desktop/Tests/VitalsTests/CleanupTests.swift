import Testing
import Foundation
@testable import Vitals

/// The uninstaller's protection rules — getting these wrong means offering
/// to trash system software.
struct AppProtectionTests {
    @Test func appleBundlesAreProtected() {
        #expect(AppInventory.isProtected(
            bundleID: "com.apple.Safari",
            url: URL(fileURLWithPath: "/Applications/Safari.app")
        ))
    }

    @Test func systemPathsAreProtected() {
        #expect(AppInventory.isProtected(
            bundleID: "org.example.tool",
            url: URL(fileURLWithPath: "/System/Applications/Whatever.app")
        ))
    }

    @Test func vitalsItselfIsProtected() {
        #expect(AppInventory.isProtected(
            bundleID: "com.syntaxlabtechnology.vitals",
            url: URL(fileURLWithPath: "/Applications/Vitals.app")
        ))
    }

    @Test func everyVitalsChannelIsProtected() {
        #expect(AppInventory.isProtected(
            bundleID: "com.syntaxlabtechnology.vitals.dev",
            url: URL(fileURLWithPath: "/Applications/Vitals Dev.app")
        ))
    }

    @Test func ordinaryAppsAreNot() {
        #expect(!AppInventory.isProtected(
            bundleID: "com.spotify.client",
            url: URL(fileURLWithPath: "/Applications/Spotify.app")
        ))
    }
}

/// Leftover discovery must never build dangerous paths from hostile or
/// degenerate inputs (a malformed Info.plist, a one-letter app name).
struct LeftoverScannerTests {
    @Test func nameVariantsCoverCommonConventions() {
        let variants = LeftoverScanner.nameVariants("Maestro Studio")
        #expect(variants.contains("Maestro Studio"))
        #expect(variants.contains("MaestroStudio"))
        #expect(variants.contains("maestro-studio"))
        #expect(variants.contains("maestro_studio"))
        #expect(variants.contains("maestro studio"))
    }

    @Test func shortNamesProduceNothing() {
        #expect(LeftoverScanner.nameVariants("A").isEmpty)
        #expect(LeftoverScanner.nameVariants(" ").isEmpty)
    }

    @Test func bundleIDValidation() {
        #expect(LeftoverScanner.isValidBundleID("com.spotify.client"))
        #expect(LeftoverScanner.isValidBundleID("org.mozilla.firefox"))
        #expect(!LeftoverScanner.isValidBundleID("nodots"))
        #expect(!LeftoverScanner.isValidBundleID("../../etc"))
        #expect(!LeftoverScanner.isValidBundleID("com.evil/*"))
        #expect(!LeftoverScanner.isValidBundleID("com..double"))
    }

    @Test func candidatesStayInsideUserDomain() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let candidates = LeftoverScanner.candidatePaths(bundleID: "com.example.app", appName: "Example App", home: home)
        #expect(!candidates.isEmpty)
        for (url, _) in candidates {
            #expect(url.path.hasPrefix("/Users/test/"), "escaped home: \(url.path)")
            #expect(url.path != "/Users/test", "bare home offered for deletion")
        }
    }

    @Test func invalidBundleIDContributesNoPaths() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let bad = LeftoverScanner.candidatePaths(bundleID: "../../etc", appName: "X", home: home)
        #expect(bad.isEmpty)  // name too short AND bundle id invalid
    }

    @Test func expectedLocationsAreProbed() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let paths = LeftoverScanner.candidatePaths(bundleID: "com.example.app", appName: "Example", home: home)
            .map { $0.0.path }
        #expect(paths.contains("/Users/test/Library/Application Support/com.example.app"))
        #expect(paths.contains("/Users/test/Library/Caches/Example"))
        #expect(paths.contains("/Users/test/Library/Preferences/com.example.app.plist"))
        #expect(paths.contains("/Users/test/Library/Containers/com.example.app"))
        #expect(paths.contains("/Users/test/Library/Saved Application State/com.example.app.savedState"))
    }

    /// The broadened catalog (matching Mole) must still build only confined,
    /// id-keyed paths — never a shared system folder.
    @Test func broadenedLocationsAreProbed() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let paths = LeftoverScanner.candidatePaths(bundleID: "com.example.app", appName: "Example", home: home)
            .map { $0.0.path }
        #expect(paths.contains("/Users/test/Library/Caches/com.apple.nsurlsessiond/Downloads/com.example.app"))
        #expect(paths.contains("/Users/test/Library/Application Support/com.apple.sharedfilelist/com.example.app.sfl4"))
        #expect(paths.contains("/Users/test/Library/WebKit/com.apple.WebKit.WebContent/com.example.app"))
        #expect(paths.contains("/Users/test/Library/Input Methods/com.example.app.app"))
        #expect(paths.contains("/Users/test/Library/Application Support/CrashReporter/Example"))
        // Even these Apple-namespaced container paths end in the app's own id,
        // so they stay inside the home folder and target only this app.
        for p in paths { #expect(p.hasPrefix("/Users/test/")) }
    }

    /// Vendor-nested probing targets the *product* subfolder under a brand, not
    /// the shared vendor root (which other apps use), and stays in the home.
    @Test func vendorNestedTargetsProductNotVendorRoot() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let paths = LeftoverScanner.vendorNestedCandidates(
            bundleID: "com.google.Chrome", appName: "Google Chrome", home: home
        ).map { $0.0.path }
        #expect(paths.contains("/Users/test/Library/Application Support/Google/Chrome"))
        // Never the bare vendor folder — that would nuke other Google apps' data.
        #expect(!paths.contains("/Users/test/Library/Application Support/Google"))
        #expect(!paths.contains("/Users/test/Library/Caches/Google"))
        for p in paths {
            #expect(p.hasPrefix("/Users/test/Library/"), "escaped: \(p)")
            let tail = p.replacingOccurrences(of: "/Users/test/Library/", with: "")
            #expect(tail.split(separator: "/").count >= 3, "not a product subfolder: \(p)")
        }
    }

    @Test func vendorNestedNeedsThreePartID() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        // Two-part ids have no vendor component to nest under.
        #expect(LeftoverScanner.vendorNestedCandidates(bundleID: "com.slack", appName: "Slack", home: home).isEmpty)
        #expect(LeftoverScanner.vendorNestedCandidates(bundleID: nil, appName: "Slack", home: home).isEmpty)
    }

    /// Group-container matching identifies the *owner* (the remainder after the
    /// team-id / "group." prefix) and requires it to equal the bundle id exactly,
    /// so a sibling app whose id extends this one's is never captured.
    @Test func groupContainerMatchesOwnerExactly() {
        #expect(LeftoverScanner.groupContainerBelongsToBundle("com.example.app", "com.example.app"))
        #expect(LeftoverScanner.groupContainerBelongsToBundle("ABCDE12345.com.example.app", "com.example.app"))
        #expect(LeftoverScanner.groupContainerBelongsToBundle("group.com.example.app", "com.example.app"))
        // A separate installed sibling whose id extends this one's must not match.
        #expect(!LeftoverScanner.groupContainerBelongsToBundle("ABCDE12345.com.example.app.beta", "com.example.app"))
        #expect(!LeftoverScanner.groupContainerBelongsToBundle("group.com.example.app.beta", "com.example.app"))
        #expect(!LeftoverScanner.groupContainerBelongsToBundle("com.example.applications", "com.example.app"))
        #expect(!LeftoverScanner.groupContainerBelongsToBundle("anything", "nodots"))
    }

    /// Recent-items shared-file-lists are matched by id + the `.sfl*` family,
    /// never a different app or a non-sfl file.
    @Test func sharedFileListMatchesRecentItemsByID() {
        #expect(LeftoverScanner.isSharedFileList("com.example.app.sfl4", "com.example.app"))
        #expect(LeftoverScanner.isSharedFileList("com.example.app.sfl3", "com.example.app"))
        #expect(LeftoverScanner.isSharedFileList("com.example.app.sfl", "com.example.app"))
        #expect(!LeftoverScanner.isSharedFileList("com.example.app.plist", "com.example.app"))
        #expect(!LeftoverScanner.isSharedFileList("com.example.application.sfl4", "com.example.app"))
        #expect(!LeftoverScanner.isSharedFileList("com.other.app.sfl4", "com.example.app"))
        // A longer id's sfl must not be mistaken for a shorter app id's.
        #expect(!LeftoverScanner.isSharedFileList("com.foo.bar.sfl4", "com.foo"))
    }

    /// End-to-end against a temp home: the scan must catch the nested `.sfl4`
    /// recents file, the exact `.ShipIt` updater cache, and a UUID-named daemon
    /// container (matched via its metadata id) — and crucially must NOT touch a
    /// *separate installed* app whose id extends the target's (`com.example.app.beta`),
    /// whose Containers hold real user documents.
    @Test func scanFindsAppJunkButNotASiblingApp() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("vitals-leftover-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }

        func make(_ relative: String, file: Bool = false, contents: String = "x") throws {
            let url = home.appendingPathComponent(relative)
            try fm.createDirectory(at: file ? url.deletingLastPathComponent() : url,
                                   withIntermediateDirectories: true)
            if file { try contents.write(to: url, atomically: true, encoding: .utf8) }
        }

        // The target app's own junk — should be found:
        try make("Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.example.app.sfl4", file: true)
        try make("Library/Caches/com.example.app.ShipIt")           // Squirrel updater cache
        let daemon = "Library/Daemon Containers/\(UUID().uuidString)"
        try make("\(daemon)/Data")
        let metaURL = home.appendingPathComponent("\(daemon)/.com.apple.containermanagerd.metadata.plist")
        try (["MCMMetadataIdentifier": "com.example.app"] as NSDictionary).write(to: metaURL)

        // The target app's own group container — should be found:
        try make("Library/Group Containers/ABCDE12345.com.example.app")

        // A separate installed sibling app — its data must be left untouched:
        try make("Library/Containers/com.example.app.beta")         // sandbox documents!
        try make("Library/Caches/com.example.app.beta")
        try make("Library/Caches/com.example.application")
        try make("Library/Group Containers/ABCDE12345.com.example.app.beta")

        let found = LeftoverScanner.scan(bundleID: "com.example.app", appName: "Example", home: home)
        let names = Set(found.map(\.id.lastPathComponent))
        #expect(names.contains("com.example.app.sfl4"))
        #expect(names.contains("com.example.app.ShipIt"))
        #expect(found.contains { $0.id.path.contains("/Daemon Containers/") })
        #expect(names.contains("ABCDE12345.com.example.app"))      // own group container
        // The sibling app's data is never captured.
        #expect(!found.contains { $0.id.path.contains("com.example.app.beta") })
        #expect(!names.contains("com.example.application"))
    }
}

struct CLIInventoryTests {
    @Test func treeParserKeepsScopedNamesAndRejectsTraversal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitals-cli-(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("@scope/tool"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("plain-cli"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let output = """
        (root.path) (3)
        ├── @scope/tool@1.2.3
        ├── plain-cli@4.5.6
        └── ../outside@9.9.9
        """
        let rows = CLIInventory.parseTreePackages(output, manager: .bun)

        #expect(Set(rows.map(\.name)) == Set(["@scope/tool", "plain-cli"]))
        #expect(rows.allSatisfy { $0.cliManager == .bun })
    }
}

/// The complete uninstall reaches system-domain files and removes them as root,
/// so the system catalog must stay confined and the privileged script must stay
/// auditable: allowlisted roots only, never /System, never com.apple.*, never a
/// bare path.
struct UninstallSystemTests {
    @Test func systemCandidatesStayInAllowlistedRoots() {
        let candidates = LeftoverScanner.systemCandidates(bundleID: "com.example.app", appName: "Example App")
        #expect(!candidates.isEmpty)
        for (url, _) in candidates {
            #expect(url.path.hasPrefix("/Library/"), "outside /Library: \(url.path)")
            #expect(!url.path.hasPrefix("/System"))
            #expect(!url.lastPathComponent.hasPrefix("com.apple."))
        }
    }

    @Test func shortOrGenericNamesGateSystemNameMatches() {
        #expect(!LeftoverScanner.isSafeSystemName("App"))      // too short
        #expect(!LeftoverScanner.isSafeSystemName("Updater"))  // generic word
        #expect(LeftoverScanner.isSafeSystemName("Maestro"))
        // A short name yields only bundle-id-derived system candidates.
        let candidates = LeftoverScanner.systemCandidates(bundleID: "com.example.app", appName: "App")
        #expect(candidates.allSatisfy { $0.0.path.contains("com.example.app") })
    }

    @Test func removalScriptIsBoundedAndSafe() throws {
        let script = try #require(AppUninstaller.systemRemovalScript(for: [
            URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.app.plist"),
            URL(fileURLWithPath: "/Users/Shared/Example"),
            URL(fileURLWithPath: "/private/var/db/receipts/com.example.app.bom"),
            // all of these must be dropped:
            URL(fileURLWithPath: "/System/Library/LaunchDaemons/com.apple.x.plist"),
            URL(fileURLWithPath: "/Library/LaunchDaemons/com.apple.something.plist"),
            URL(fileURLWithPath: "/etc/passwd"),
            URL(fileURLWithPath: "/"),
        ]))
        #expect(!script.contains("/System"))
        #expect(!script.contains("com.apple."))
        #expect(!script.contains("/etc/passwd"))
        #expect(script.contains("/Library/LaunchDaemons/com.example.app.plist"))
        #expect(script.contains("/Users/Shared/Example"))
        #expect(script.contains("/private/var/db/receipts/com.example.app.bom"))
        for line in script.split(separator: "\n") where line.hasPrefix("rm ") {
            #expect(line.hasPrefix("rm -rf '/"), "unsafe rm line: \(line)")
        }
    }

    @Test func removalScriptNilWhenNothingValid() {
        #expect(AppUninstaller.systemRemovalScript(for: [
            URL(fileURLWithPath: "/System/x"),
            URL(fileURLWithPath: "/etc/x"),
        ]) == nil)
    }

    @Test func removalScriptAllowsConfirmedAppBundleOnly() throws {
        let script = try #require(AppUninstaller.systemRemovalScript(for: [
            URL(fileURLWithPath: "/Applications/AlDente.app"),
            URL(fileURLWithPath: "/Applications/loose-file.txt"),     // not .app → dropped
            URL(fileURLWithPath: "/System/Applications/Mail.app"),    // /System → dropped
        ]))
        #expect(script.contains("rm -rf '/Applications/AlDente.app'"))
        #expect(!script.contains("loose-file.txt"))
        #expect(!script.contains("/System"))
    }

    /// Embedded helpers that share the app's vendor namespace are harvested;
    /// embedded *shared* third-party frameworks (whose data other apps use) are
    /// not — getting this wrong would delete another app's files.
    @Test func helperHarvestingStaysInVendorNamespace() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("VitalsHelperTest-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Example.app")
        defer { try? fm.removeItem(at: root) }

        func writeHelper(_ relative: String, id: String) throws {
            let dir = app.appendingPathComponent("Contents/\(relative)/Contents")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": id]
            try (plist as NSDictionary).write(to: dir.appendingPathComponent("Info.plist"))
        }
        try writeHelper("Library/LoginItems/Updater.app", id: "com.example.app.updater")  // same vendor → kept
        try writeHelper("XPCServices/Net.xpc", id: "com.example.app.net")                  // same vendor → kept
        try writeHelper("PlugIns/Share.appex", id: "org.sparkle-project.Sparkle")          // shared lib → dropped
        try writeHelper("Library/LoginItems/Apple.app", id: "com.apple.something")          // Apple → dropped

        let ids = LeftoverScanner.helperBundleIDs(appURL: app, mainBundleID: "com.example.app")
        #expect(Set(ids) == ["com.example.app.updater", "com.example.app.net"])
    }

    @Test func helperHarvestingNeedsValidMainID() {
        let app = URL(fileURLWithPath: "/Applications/Whatever.app")
        #expect(LeftoverScanner.helperBundleIDs(appURL: app, mainBundleID: "nodots").isEmpty)
    }

    @Test func homebrewCaskMatchesNormalizedName() {
        let casks = ["google-chrome", "visual-studio-code", "slack"]
        #expect(LeftoverScanner.homebrewCask(appName: "Google Chrome", installedCasks: casks) == "google-chrome")
        #expect(LeftoverScanner.homebrewCask(appName: "Slack", installedCasks: casks) == "slack")
        #expect(LeftoverScanner.homebrewCask(appName: "Some Unknown App", installedCasks: casks) == nil)
    }

    @Test func homebrewCaskOwnershipRequiresExactBundlePath() {
        let app = URL(fileURLWithPath: "/Applications/Docker.app")
        #expect(!LeftoverScanner.caskOwns(
            appURL: app,
            token: "docker",
            listOutput: "/Applications/Other.app\n"
        ))
        #expect(LeftoverScanner.caskOwns(
            appURL: app,
            token: "docker",
            listOutput: "/Applications/Docker.app\n"
        ))
    }
}

/// Cleanup must keep Apple's system caches and crash reports off the menu.
struct DiskCleanerTests {
    @Test func appleCachesAreProtected() {
        #expect(!DiskCleaner.shouldOfferCache(named: "com.apple.WebKit.WebContent"))
        #expect(!DiskCleaner.shouldOfferCache(named: "CloudKit"))
        #expect(!DiskCleaner.shouldOfferCache(named: "Homebrew"))  // its own category
    }

    @Test func thirdPartyCachesAreOffered() {
        #expect(DiskCleaner.shouldOfferCache(named: "Google"))
        #expect(DiskCleaner.shouldOfferCache(named: "com.spotify.client"))
    }

    @Test func crashReportsAreKept() {
        #expect(!DiskCleaner.shouldOfferLog(named: "DiagnosticReports"))
        #expect(!DiskCleaner.shouldOfferLog(named: "CrashReporter"))
        #expect(DiskCleaner.shouldOfferLog(named: "Google"))
    }
}

/// Browser-cache cleaning must clear only regenerable cache folders — never a
/// profile's cookies, history, bookmarks or saved logins.
struct BrowserCacheTests {
    @Test func clearsOnlyCacheFoldersNeverProfileData() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("VitalsBrowserTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }

        let profile = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        // Cache folders that SHOULD be offered.
        for sub in ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage"] {
            try fm.createDirectory(at: profile.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        // Profile data that must NEVER be offered (siblings of the caches).
        for data in ["Cookies", "History", "Bookmarks", "Login Data", "Web Data"] {
            try fm.createDirectory(at: profile.appendingPathComponent(data), withIntermediateDirectories: true)
        }

        // The temp dir is a symlink (/var → /private/var); enumeration resolves
        // it, so compare on resolved paths.
        let dirs = DiskCleaner.browserCacheDirs(home: home)
        let paths = dirs.map { $0.resolvingSymlinksInPath().path }
        func resolved(_ sub: String) -> String {
            profile.appendingPathComponent(sub).resolvingSymlinksInPath().path
        }
        #expect(paths.contains(resolved("Cache")))
        #expect(paths.contains(resolved("Code Cache")))
        #expect(paths.contains(resolved("Service Worker/CacheStorage")))
        // The crucial guarantee: nothing that isn't a cache.
        for path in paths {
            let last = (path as NSString).lastPathComponent
            #expect(last.contains("Cache") || last == "CacheStorage" || last == "ScriptCache" || last == "Firefox",
                    "non-cache path offered: \(path)")
            #expect(!path.contains("/Cookies"))
            #expect(!path.contains("/History"))
            #expect(!path.contains("/Bookmarks"))
            #expect(!path.contains("/Login Data"))
        }
    }

    @Test func quickScanOffersBrowserAndDeviceCategories() {
        let kinds = Set(DiskCleaner.scan(depth: .quick).map(\.kind))
        #expect(kinds.contains(.browserCaches))
        #expect(kinds.contains(.deviceSupport))
        // Both are user-domain — no admin in Quick.
        #expect(!CleanupCategory.Kind.browserCaches.requiresAdmin)
        #expect(!CleanupCategory.Kind.deviceSupport.requiresAdmin)
    }
}

/// Device firmware / backup cleaning matches Mole: firmware caches are safe and
/// age-gated; iOS backups are opt-in, off by default, and flagged irreversible.
struct DeviceCleanupTests {
    @Test func firmwareIsAgeGatedAndExtensionScoped() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("VitalsFirmwareTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let dir = home.appendingPathComponent("Library/iTunes/iPhone Software Updates")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        func write(_ name: String, ageDays: Int) throws {
            let url = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            let date = Date().addingTimeInterval(-Double(ageDays) * 86_400)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        try write("old.ipsw", ageDays: 30)      // eligible
        try write("recent.ipsw", ageDays: 2)    // too new
        try write("notes.txt", ageDays: 30)     // wrong extension

        let names = Set(DiskCleaner.iosFirmwareFiles(home: home).map(\.lastPathComponent))
        #expect(names == ["old.ipsw"])
    }

    @Test func deviceBackupsAreDeepDestructiveAndUserDomain() {
        let kind = CleanupCategory.Kind.deviceBackups
        #expect(kind.isDestructive)
        #expect(!kind.requiresAdmin)             // backups are user-owned, no admin
        #expect(kind.minimumDepth == .deep)
        // Only Deep surfaces it, and it's never auto-selected (selection starts empty).
        #expect(!Set(DiskCleaner.scan(depth: .quick).map(\.kind)).contains(.deviceBackups))
        #expect(Set(DiskCleaner.scan(depth: .deep).map(\.kind)).contains(.deviceBackups))
    }

    @Test func firmwareIsQuickSafeAndNotDestructive() {
        let kind = CleanupCategory.Kind.deviceFirmware
        #expect(!kind.isDestructive)
        #expect(!kind.requiresAdmin)
        #expect(Set(DiskCleaner.scan(depth: .quick).map(\.kind)).contains(.deviceFirmware))
    }

    @Test func destructiveKindsAreEnumerated() {
        // The destructive set is consciously enumerated: irreversible-if-gone
        // data only (device backups, and AI chat transcripts moved to the Trash).
        let destructive = CleanupCategory.Kind.allCases.filter(\.isDestructive)
        #expect(destructive == [.deviceBackups, .aiHistory])
    }
}

/// Deep clean reaches system files as root, so the generated script must stay
/// auditable: only allowlisted roots, always age-gated, never the sealed system
/// volume or a bare path. Quick mode must never surface an admin category.
struct DeepCleanTests {
    @Test func quickScanHasNoAdminCategories() {
        let quick = DiskCleaner.scan(depth: .quick)
        #expect(!quick.isEmpty)
        #expect(quick.allSatisfy { !$0.kind.requiresAdmin })
    }

    @Test func deepScanAddsAdminCategories() {
        let deep = DiskCleaner.scan(depth: .deep)
        let adminKinds = Set(deep.filter { $0.kind.requiresAdmin }.map(\.kind))
        #expect(adminKinds.contains(.systemCaches))
        #expect(adminKinds.contains(.crashReports))
        #expect(adminKinds.contains(.gpuCaches))
        #expect(deep.count > DiskCleaner.scan(depth: .quick).count)
    }

    @Test func systemScriptIsAgeGatedAndBounded() {
        let allSystem: Set<CleanupCategory.Kind> = [.systemCaches, .systemLogs, .crashReports, .systemTemp, .gpuCaches]
        let script = DiskCleaner.systemCleanScript(for: allSystem)

        let deleteLines = script.split(separator: "\n").filter { $0.contains("-delete") }
        #expect(!deleteLines.isEmpty)
        for line in deleteLines {
            #expect(line.contains("-mtime +"), "ungated delete: \(line)")
            #expect(line.contains("-type f"), "non-file delete: \(line)")
            let allowed = line.contains("/Library/Caches")
                || line.contains("/private/var/log")
                || line.contains("/Library/Logs/DiagnosticReports")
                || line.contains("/private/tmp")
                || line.contains("/private/var/tmp")
                || line.contains("/private/var/folders")  // GPU caches
            #expect(allowed, "unexpected root: \(line)")
        }
        #expect(!script.contains("/System"))
        #expect(!script.contains("rm -rf"))
        #expect(!script.contains("find '/' "))
    }

    @Test func nonAdminKindsProduceNoDeletes() {
        #expect(!DiskCleaner.systemCleanScript(for: []).contains("-delete"))
        #expect(!DiskCleaner.systemCleanScript(for: [.appCaches, .logs, .trash]).contains("-delete"))
    }
}

/// When the in-process cleanup can't delete a user item (root-owned cache,
/// permission-locked Trash), it retries as root — but the privileged script
/// must stay confined to the same user cleanup roots, never escaping the home
/// folder or reaching the system volume.
struct CleanupFallbackTests {
    @Test func fallbackScriptStaysInUserCleanupRoots() throws {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let script = try #require(DiskCleaner.userCleanFallbackScript(for: [
            home.appendingPathComponent(".Trash/Old App.app"),
            home.appendingPathComponent("Library/Caches/com.example.app"),
            home.appendingPathComponent("Library/Logs/Example"),
            home.appendingPathComponent(".deno"),            // whole-dir cache item
            // all of these must be dropped:
            home.appendingPathComponent("Documents/thesis.pages"),
            home.appendingPathComponent("Desktop/photo.jpg"),
            home.appendingPathComponent("Library/Mobile Documents/iCloud~thing"),
            URL(fileURLWithPath: "/System/Library/Caches/x"),
            URL(fileURLWithPath: "/etc/passwd"),
            home,                                            // bare home
        ], home: home))

        #expect(script.contains("rm -rf '/Users/test/.Trash/Old App.app'"))
        #expect(script.contains("rm -rf '/Users/test/Library/Caches/com.example.app'"))
        #expect(script.contains("rm -rf '/Users/test/Library/Logs/Example'"))
        #expect(script.contains("rm -rf '/Users/test/.deno'"))
        #expect(!script.contains("Documents"))
        #expect(!script.contains("Desktop"))
        #expect(!script.contains("Mobile Documents"))
        #expect(!script.contains("/System"))
        #expect(!script.contains("/etc/passwd"))
        for line in script.split(separator: "\n") where line.hasPrefix("rm ") {
            #expect(line.hasPrefix("rm -rf '/Users/test/"), "escaped home: \(line)")
        }
    }

    @Test func fallbackScriptNilWhenNothingValid() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        #expect(DiskCleaner.userCleanFallbackScript(for: [
            URL(fileURLWithPath: "/System/x"),
            URL(fileURLWithPath: "/etc/passwd"),
            home.appendingPathComponent("Documents/file"),
        ], home: home) == nil)
    }
}
