import Foundation
import AppKit
import CoreAudio
import AudioToolbox

enum SystemControl {
    static func setVolume(_ level: Double) -> String? {
        guard let device = defaultOutputDevice() else { return "No audio output device" }
        var volume = Float32(min(1, max(0, level)))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        return status == noErr ? nil : "Volume change failed (\(status))"
    }

    static func volume() -> Double? {
        guard let device = defaultOutputDevice() else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Double(volume)
    }

    static func muted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    static func setMuted(_ muted: Bool) -> String? {
        guard let device = defaultOutputDevice() else { return "No audio output device" }
        var value = UInt32(muted ? 1 : 0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr ? nil : "Mute change failed (\(status))"
    }

    @MainActor
    static func setClipboard(_ text: String) -> String? {
        let board = NSPasteboard.general
        board.clearContents()
        return board.setString(text, forType: .string) ? nil : "Clipboard write failed"
    }

    @MainActor
    static func clipboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    @MainActor
    static func open(_ string: String) -> String? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return "Only http and https links open remotely"
        }
        return NSWorkspace.shared.open(url) ? nil : "macOS could not open the link"
    }

    @MainActor
    static func locate() {
        NSSound(named: "Glass")?.play()
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
