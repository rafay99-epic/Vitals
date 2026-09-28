import Testing
import Foundation
import AppKit
@testable import Vitals

/// Locks the power-driven sampling lifecycle: the timer must tear down on
/// system sleep and rebuild on wake (no sensor reads while suspended), and the
/// `SensorSampler` must honor the GPU/power skip flags so a menu-bar-only tick
/// costs less than a window-open one.
@MainActor
struct SleepWakeTests {
    private func makeModel() -> (VitalsModel, AppSettings) {
        let name = "vitals.test.sleepwake.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: suite)
        return (VitalsModel(settings: settings), settings)
    }

    @Test func sleepTearsDownTheTimerWakeRebuildsIt() {
        let (model, _) = makeModel()
        model.start()
        #expect(model.isSamplingTimerActive)

        // Posting the workspace notifications drives the real observer path —
        // no need to actually sleep the Mac.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(!model.isSamplingTimerActive)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(model.isSamplingTimerActive)
    }

    @Test func doubleSleepAndDoubleWakeAreNoOps() {
        let (model, _) = makeModel()
        model.start()
        #expect(model.isSamplingTimerActive)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(!model.isSamplingTimerActive)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(model.isSamplingTimerActive)
        // A second wake must not spawn a second timer.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(model.isSamplingTimerActive)
    }
}

/// The sampler's needs are the idle-tick cost gate: with nothing visible, the
/// snapshot carries nil and the model holds the last reading rather than paying
/// an IOReport round-trip or a process sweep.
@MainActor
struct SamplerSkipTests {
    @Test func skippedReadsYieldNil() async {
        let snapshot = await SensorSampler().sample(.init())
        #expect(snapshot.gpu == nil)
        #expect(snapshot.power == nil)
        #expect(snapshot.topProcesses.isEmpty)
        #expect(snapshot.network?.wifi == nil)
    }
}
