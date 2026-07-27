import Testing
import Foundation
@testable import Vitals

/// Locks the GPU-acceleration / Liquid Glass defaults and gating: the app must
/// ship lean (glass off, acceleration on), and glass must be impossible while
/// acceleration is off.
@MainActor
struct GPUAccelerationSettingsTests {
    // A unique suite per test (keyed to the calling test's name) so parallel
    // tests never share a UserDefaults store and wipe each other — the cause of
    // a CI-only flake. `#function` resolves at the call site to the test method.
    private func freshSettings(_ id: String = #function) -> AppSettings {
        let name = "vitals.test.gpuaccel.\(id)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return AppSettings(defaults: suite, configURL: nil)
    }

    @Test func shipsLeanByDefault() {
        let settings = freshSettings()
        #expect(settings.gpuAcceleration == true)
        #expect(settings.liquidGlass == false)
    }

    @Test func glassRequiresAcceleration() {
        let settings = freshSettings()
        settings.liquidGlass = true
        settings.gpuAcceleration = false
        #expect(settings.glassEnabled == false)
    }

    @Test func animationsFollowAcceleration() {
        let settings = freshSettings()
        settings.gpuAcceleration = false
        #expect(settings.animationsEnabled == false)
    }
}

@MainActor
struct ApplicationScanSettingsTests {
    @Test func extendedInventoryIsOffByDefaultAndPersists() {
        let name = "vitals.test.appscan.\(#function)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: suite, configURL: nil)

        #expect(settings.scanCLIAndSystemApplications == false)
        settings.scanCLIAndSystemApplications = true
        #expect(suite.bool(forKey: "scanCLIAndSystemApplications") == true)
    }
}
