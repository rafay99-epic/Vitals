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
