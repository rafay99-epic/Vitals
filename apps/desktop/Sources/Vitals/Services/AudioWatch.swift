import AudioToolbox
import CoreAudio
import Foundation

/// Watches the default output's volume and mute, following output switches
/// (speakers to headphones). Changes from the keyboard, Control Center or a
/// phone all land here. `onChange` runs on the main actor, coalesced so a
/// dragged slider sends a handful of updates, not hundreds.
@MainActor
final class AudioWatch {
    struct State: Equatable, Sendable {
        var volume: Double?
        var muted: Bool?
    }

    var onChange: ((State) -> Void)?
    private(set) var state = State()

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var pending: DispatchWorkItem?
    private static let coalesce: TimeInterval = 0.15

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static let defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
    private static let watched = [
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput),
        address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput),
    ]

    private lazy var outputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.rebind() }
    }
    private lazy var valueListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.schedule() }
    }

    func start() {
        var output = Self.defaultOutput
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &output, .main, outputListener)
        rebind()
    }

    private func rebind() {
        for var address in Self.watched where device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, valueListener)
        }
        device = SystemControl.defaultOutputDevice() ?? AudioObjectID(kAudioObjectUnknown)
        for var address in Self.watched where device != kAudioObjectUnknown {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, valueListener)
        }
        schedule()
    }

    private func schedule() {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.read() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesce, execute: work)
    }

    private func read() {
        pending = nil
        let next = State(volume: SystemControl.volume(), muted: SystemControl.muted())
        guard next != state else { return }
        state = next
        onChange?(next)
    }
}
