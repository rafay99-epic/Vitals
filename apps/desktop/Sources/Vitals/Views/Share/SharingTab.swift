import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SharingTab: View {
    @Environment(ShareModel.self) private var share

    var body: some View {
        @Bindable var share = share
        MetricScroll {
            FilesCard()
            RecentCard()
            ClipboardCard()
        }
        .sheet(item: $share.draft) { _ in SendFilesSheet() }
    }
}

private struct FilesCard: View {
    @Environment(ShareModel.self) private var share
    @Environment(RemoteModel.self) private var remote

    var body: some View {
        @Bindable var share = share
        SectionCard(title: "Files", symbol: "tray.and.arrow.down") {
            settingsRow("Receive files into") {
                HStack(spacing: 8) {
                    Label(ShareFormat.folder(share.folder), systemImage: "folder")
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(share.folder.path)
                    Button("Change…") { chooseFolder() }
                        .controlSize(.small)
                }
            }
            SwitchRow(
                label: "Phones can browse the whole Mac",
                caption: remote.browseEverything ? "Everything you can open, except Vitals' own data and Keychains" : "Desktop, Documents, Downloads and Pictures",
                isOn: Binding(get: { remote.browseEverything }, set: { remote.setBrowseEverything($0) })
            )
            SwitchRow(
                label: "Start without asking from my phones",
                caption: "Phones with Files on. Bigger than the largest drop still asks.",
                isOn: $share.autoAccept
            )
            SwitchRow(
                label: "Ask before receiving from the web",
                caption: "Browser sessions always ask when this is on.",
                isOn: $share.askWeb
            )
            settingsRow("Largest drop") {
                Picker("Largest drop", selection: $share.largestGB) {
                    ForEach(ShareModel.largestOptions, id: \.self) { Text("\($0) GB").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Or drop files on the menu bar or Dock icon, or use Services › Send to Phone in Finder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Send Files…") { share.openDraft() }
                    .disabled(remote.state != .running || share.phones.isEmpty)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Received files are saved here."
        panel.directoryURL = share.folder.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        share.setFolder(url)
    }
}

private struct RecentCard: View {
    @Environment(ShareModel.self) private var share

    var body: some View {
        SectionCard(title: "Recent", symbol: "clock") {
            if share.drops.isEmpty {
                Text("Empty").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(share.drops.prefix(30)) { drop in
                        RecentRow(drop: drop)
                        if drop.id != share.drops.prefix(30).last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct RecentRow: View {
    @Environment(ShareModel.self) private var share
    let drop: Drop

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(symbol: DropLook.symbol(drop), tint: DropLook.tint(drop), size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: drop.isOutgoing ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(drop.isOutgoing ? Color.blue : Color.green)
                    Text(ShareModel.label(drop))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    GatekeeperTag(drop: drop)
                }
                if drop.state.isActive {
                    ProgressView(value: drop.fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            status
            actions
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        let peer = "\(drop.isOutgoing ? "to" : "from") \(drop.phone.name)"
        switch drop.state {
        case .running, .paused:
            return ([ShareFormat.progress(drop.done, of: drop.bytes), drop.route?.label, peer] as [String?]).compactMap { $0 }.joined(separator: " · ")
        case .waiting:
            return "Open Vitals on \(drop.phone.name) · \(ShareFormat.size(drop.bytes))"
        case .failed:
            return (["Stopped at \(ShareFormat.progress(drop.done, of: drop.bytes))", drop.error, DropLook.when(drop.updated)] as [String?])
                .compactMap { $0 }.joined(separator: " · ")
        default:
            let count = drop.files.count > 1 ? ShareFormat.files(drop.files.count) : nil
            return ([count, ShareFormat.size(drop.bytes), peer, DropLook.when(drop.updated)] as [String?]).compactMap { $0 }.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch drop.state {
        case .running:
            Text("\(drop.percent)%")
                .font(.system(.callout, design: .rounded, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
        case .paused: Text("Paused").foregroundStyle(.secondary)
        case .waiting: Text("Waiting").foregroundStyle(.orange)
        case .asking: Text("Asking").foregroundStyle(.orange)
        case .done: Text("Done").foregroundStyle(.green)
        case .failed: Text("Failed").foregroundStyle(.red)
        case .cancelled: Text("Cancelled").foregroundStyle(.secondary)
        case .declined: Text("Declined").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch drop.state {
        case .running, .paused:
            DropControls(drop: drop)
        case .waiting:
            Button("Cancel") { share.cancel(drop.id) }.controlSize(.small)
        case .asking:
            if drop.isOutgoing {
                Button("Cancel") { share.cancel(drop.id) }.controlSize(.small)
            } else {
                Button("Decline") { share.decide(drop.id, accept: false) }.controlSize(.small)
                Button("Accept") { share.decide(drop.id, accept: true) }.controlSize(.small)
            }
        case .done where !drop.isOutgoing:
            Button { share.reveal(drop.id) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
        case .failed, .cancelled:
            if share.canRetry(drop) { Button("Retry") { share.retry(drop) }.controlSize(.small) }
        default:
            EmptyView()
        }
    }
}

struct DropControls: View {
    @Environment(ShareModel.self) private var share
    let drop: Drop

    var body: some View {
        HStack(spacing: 2) {
            Button { share.setPaused(drop.id, drop.state != .paused) } label: {
                Image(systemName: drop.state == .paused ? "play.fill" : "pause.fill")
            }
            .help(drop.state == .paused ? "Resume" : "Pause")
            Button { share.cancel(drop.id) } label: { Image(systemName: "xmark.circle.fill") }
                .help("Cancel")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .font(.system(size: 13))
    }
}

private struct GatekeeperTag: View {
    let drop: Drop

    var body: some View {
        let kinds = Set(DropFiles.topLevelNames(drop.files.map { ($0.name, $0.path) }).compactMap(DropFiles.appKind))
        if !drop.isOutgoing, kinds.contains(.mac) {
            Label("App · quarantined", systemImage: "checkmark.shield")
                .font(.caption2.weight(.medium))
                .labelStyle(.titleAndIcon)
                .capsuleTag(.orange, fill: 0.14, horizontal: 6, vertical: 2)
                .help("macOS will check it before it runs.")
        } else if !drop.isOutgoing, kinds.contains(.android) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Android app. Marked as downloaded on this Mac.")
        }
    }
}

enum DropLook {
    static func symbol(_ drop: Drop) -> String {
        let names = DropFiles.topLevelNames(drop.files.map { ($0.name, $0.path) })
        guard names.count == 1 else { return "doc.on.doc" }
        if drop.files.count > 1 || drop.files.first?.path?.contains("/") == true { return "folder" }
        return symbol(name: names[0])
    }

    /// A single file's symbol from its name alone.
    static func symbol(name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch DropFiles.appKind(name) {
        case .mac: return ext == "dmg" ? "externaldrive" : "shippingbox"
        case .android: return "apps.iphone"
        case nil: break
        }
        guard let type = UTType(filenameExtension: ext) else { return "doc" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        return "doc"
    }

    static func tint(_ drop: Drop) -> Color { tint(symbol: symbol(drop)) }

    static func tint(symbol: String) -> Color {
        switch symbol {
        case "folder": return .blue
        case "film": return .purple
        case "photo": return .pink
        case "apps.iphone": return .green
        case "shippingbox", "externaldrive": return .brown
        case "waveform": return .red
        default: return .gray
        }
    }

    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct PhoneChoices: View {
    let phones: [RemoteDevice]
    @Binding var selection: Set<String>
    var lastUsed: String?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(phones) { phone in
                let on = selection.contains(phone.id)
                Button {
                    if on { selection.remove(phone.id) } else { selection.insert(phone.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                        Image(systemName: "iphone.gen3")
                            .foregroundStyle(phone.connected ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phone.name).font(.body.weight(.medium))
                            Text(phone.connected ? "Connected" : "Offline, it will wait")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if phone.id == lastUsed {
                            Text("Last used").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .insetCard(fill: 0.3, border: on ? 0.5 : 0.35, cornerRadius: 9, selected: on)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
