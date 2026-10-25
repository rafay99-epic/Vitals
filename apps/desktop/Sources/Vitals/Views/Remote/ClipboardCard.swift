import SwiftUI

/// Clipboard history for phones: the on/off switch, retention, what's stored, and a clear button.
struct ClipboardCard: View {
    @Environment(RemoteModel.self) private var remote
    @Environment(ShareModel.self) private var share
    @Environment(Navigator.self) private var navigator
    @State private var confirmingClear = false

    private static let keepOptions = [1, 7, 30]

    var body: some View {
        SectionCard(title: "Clipboard", symbol: "doc.on.clipboard") {
            SwitchRow(
                label: "Clipboard history for phones",
                caption: "Phones with Read clipboard see what you copy",
                isOn: Binding(get: { remote.clipHistoryEnabled }, set: { remote.setClipHistory(enabled: $0) })
            )
            if remote.clipHistoryEnabled, remote.clipReadsBlocked { blockedNotice }
            settingsRow("Keep history for") {
                Picker("Keep history for", selection: Binding(get: { remote.clipKeepDays }, set: { remote.setClipKeepDays($0) })) {
                    ForEach(Self.keepOptions, id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            Text("Passwords are always skipped. So are 1Password, Bitwarden, Passwords and Keychain Access.")
                .font(.callout)
                .foregroundStyle(.secondary)
            settingsRow("Send clipboard to phone") {
                Button { navigator.section = .settings } label: {
                    Text(share.shortcut?.display ?? "None").monospacedDigit()
                }
                .controlSize(.small)
                .help("Change it in Settings › Shortcuts")
            }
            if let stats = remote.clipStats {
                HStack {
                    Text(Self.statsLine(stats))
                        .font(.system(.callout, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    Button("Clear history") { confirmingClear = true }
                        .disabled(stats.clips <= stats.pinned)
                }
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear history", role: .destructive) { remote.clearClipHistory() }
        } message: {
            Text("Deletes every clip that isn't pinned, on this Mac and on your phones.")
        }
        .onAppear { remote.refreshClipAccess() }
    }

    private var blockedNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("macOS is blocking clipboard reads. Allow \(Channel.current.displayName) in Privacy & Security > Paste from Other Apps.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            Button("Open Paste from Other Apps") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }

    /// "Using 212 MB for 148 clips · 6 pinned", or "Empty".
    static func statsLine(_ stats: ClipStats) -> String {
        guard stats.clips > 0 else { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let size = formatter.string(fromByteCount: Int64(stats.bytes))
        let pinned = stats.pinned > 0 ? " · \(stats.pinned) pinned" : ""
        return "Using \(size) for \(stats.clips) clip\(stats.clips == 1 ? "" : "s")\(pinned)"
    }
}
