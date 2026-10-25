import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutsCard: View {
    @Environment(ShareModel.self) private var share
    @Environment(RemoteModel.self) private var remote

    var body: some View {
        SettingsCard(title: "Shortcuts", symbol: "keyboard", tint: .indigo) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HighlightLabel("Send clipboard to phone")
                        .font(.system(size: 12.5))
                    HighlightLabel(caption)
                        .font(.caption)
                        .foregroundStyle(share.hotKeyFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                Spacer()
                ShortcutRecorder()
            }
            settingsRow("Sends to") {
                Text("All phones with Read clipboard")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var caption: String {
        if share.hotKeyFailed { return "Another app already uses this shortcut" }
        return remote.isEnabled ? "Works from any app" : "Works from any app while Remote access is on"
    }
}

private struct ShortcutRecorder: View {
    @Environment(ShareModel.self) private var share
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(share.recordingShortcut ? "Type a shortcut" : share.shortcut?.display ?? "None")
                    .monospacedDigit()
                    .frame(minWidth: 96)
            }
            .controlSize(.small)
            .tint(share.recordingShortcut ? .accentColor : nil)
            .buttonStyle(.bordered)
            if share.shortcut != nil, !share.recordingShortcut {
                Button { share.setShortcut(nil) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Turn off the shortcut")
            } else if share.shortcut == nil, !share.recordingShortcut {
                Button { share.setShortcut(.sendClipboard) } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Use \(Shortcut.sendClipboard.display)")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        if share.recordingShortcut { stop() } else { start() }
    }

    private func start() {
        share.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete, kVK_ForwardDelete:
                share.setShortcut(nil)
                stop()
            default:
                guard let shortcut = Shortcut(keyCode: Int(event.keyCode), flags: event.modifierFlags) else { return nil }
                share.setShortcut(shortcut)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if share.recordingShortcut { share.recordingShortcut = false }
    }
}
