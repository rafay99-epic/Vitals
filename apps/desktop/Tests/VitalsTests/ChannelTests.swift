import Testing
import Foundation
@testable import Vitals

/// The `Channel` enum drives every channel-specific path: app name, bundle id,
/// data dir, update feed, and DMG asset. A wrong mapping here misroutes data or
/// the auto-updater, so the contract is locked.
struct ChannelTests {
    @Test func rawValuesRoundTrip() {
        #expect(Channel(rawValue: "stable") == .stable)
        #expect(Channel(rawValue: "nightly") == .nightly)
        #expect(Channel(rawValue: "dev") == .dev)
        #expect(Channel(rawValue: "bogus") == nil)
    }

    @Test func displayNamesMatchBundles() {
        #expect(Channel.stable.displayName == "Vitals")
        #expect(Channel.nightly.displayName == "Vitals Nightly")
        #expect(Channel.dev.displayName == "Vitals Dev")
    }

    @Test func badges() {
        #expect(Channel.stable.badge == nil)
        #expect(Channel.nightly.badge == "NIGHTLY")
        #expect(Channel.dev.badge == "DEV")
    }

    @Test func bundleSuffixes() {
        #expect(Channel.stable.bundleSuffix == "")
        #expect(Channel.nightly.bundleSuffix == ".nightly")
        #expect(Channel.dev.bundleSuffix == ".dev")
    }

    @Test func dataDirSuffixesAreIsolated() {
        #expect(Channel.stable.dataDirSuffix == ".vitals")
        #expect(Channel.nightly.dataDirSuffix == ".vitals-nightly")
        #expect(Channel.dev.dataDirSuffix == ".vitals-dev")
    }

    /// Dev never publishes a DMG; Stable and Nightly each have their own asset.
    @Test func assetNames() {
        #expect(Channel.stable.assetName == "Vitals.dmg")
        #expect(Channel.nightly.assetName == "Vitals-Nightly.dmg")
        #expect(Channel.dev.assetName == nil)
    }

    /// Only Nightly is a pre-release feed; only Dev has no updater; only Nightly
    /// orders by build number (Stable orders by version). These three flags are
    /// the safety contract behind the migration — a flip would regress the updater.
    @Test func feedFlags() {
        #expect(Channel.stable.isPrerelease == false)
        #expect(Channel.nightly.isPrerelease == true)
        #expect(Channel.dev.isPrerelease == false)

        #expect(Channel.stable.updatesEnabled == true)
        #expect(Channel.nightly.updatesEnabled == true)
        #expect(Channel.dev.updatesEnabled == false)

        #expect(Channel.stable.ordersByBuildNumber == false)
        #expect(Channel.nightly.ordersByBuildNumber == true)
        #expect(Channel.dev.ordersByBuildNumber == false)
    }
}

/// `Updater.buildNumber(in:)` extracts the monotonic build number from a release
/// title — the ordering key for the Nightly feed. It must read the new Nightly
/// titles and stay backward-compatible with the old Dev titles during cutover.
struct BuildNumberParseTests {
    @Test func parsesNightlyTitle() {
        #expect(Updater.buildNumber(in: "Vitals Nightly · build 42") == 42)
    }

    @Test func parsesLegacyDevTitle() {
        #expect(Updater.buildNumber(in: "Vitals Dev (latest) · build 7") == 7)
        #expect(Updater.buildNumber(in: "Vitals Dev · feature/x · build 128") == 128)
    }

    @Test func absentBuildNumberIsZero() {
        #expect(Updater.buildNumber(in: "Vitals 0.123") == 0)
        #expect(Updater.buildNumber(in: nil) == 0)
    }
}
