import Testing
import Foundation
@testable import Vitals

/// Locks the GPU-acceleration / Liquid Glass defaults and gating: the app must
/// ship lean (glass off, acceleration on), and glass must be impossible while
/// acceleration is off.
@MainActor
struct GPUAccelerationSettingsTests {
    private func freshSettings() -> AppSettings {
        let suite = UserDefaults(suiteName: "vitals.test.gpuaccel")!
        suite.removePersistentDomain(forName: "vitals.test.gpuaccel")
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
