import SwiftUI

/// One phone's page under Devices in the sidebar: short rows of its newest screenshots, photos,
/// clipboard, downloads and documents, then its folders. "See all" drills into one kind inline,
/// with a crumb back, never a second navigation level.
struct DevicePage: View {
    @Environment(DevicesModel.self) private var pages
    let deviceId: String?
    @State private var drill: DeviceDrill?
    @State private var selection: Set<String> = []

    var body: some View {
        if let deviceId, let phone = pages.phone(deviceId) {
            Group {
                switch drill {
                case let .recent(kind):
                    RecentDrill(phone: phone, kind: kind, selection: $selection) { open(nil) }
                case .clipboard:
                    ClipsDrill(phone: phone) { open(nil) }
                case nil:
                    overview(phone)
                }
            }
            .task(id: deviceId) { await pages.watch(deviceId) }
        } else {
            MetricScroll {
                EmptyStateView(
                    symbol: "iphone.slash",
                    tint: .secondary,
                    title: "Nothing found",
                    message: "No phone is sharing files. Turn on Files for a phone in Remote › Devices."
                )
            }
        }
    }

    private func overview(_ phone: PhoneDevice) -> some View {
        let page = pages.page(phone.id)
        return MetricScroll {
            PageHero(value: phone.name, subtitle: DeviceLook.status(phone)) { EmptyView() }
            if let notice = page.notice { NoticeLine(text: notice) }
            if !phone.online { OfflineCard(phone: phone) }
            ForEach([RecentKind.screenshots, .photos], id: \.self) { kind in
                if phone.online || page.recent[kind] != nil {
                    RecentCard(phone: phone, kind: kind, seeAll: { open(.recent(kind)) }, pick: { path in
                        selection = [path]
                        drill = .recent(kind)
                    })
                }
            }
            ClipsCard(phone: phone) { open(.clipboard) }
            ForEach([RecentKind.downloads, .documents], id: \.self) { kind in
                if phone.online || page.recent[kind] != nil {
                    RecentCard(phone: phone, kind: kind, seeAll: { open(.recent(kind)) }, pick: { _ in })
                }
            }
            if phone.online { PhoneFilesCard(device: phone) }
        }
    }

    private func open(_ next: DeviceDrill?) {
        selection = []
        drill = next
    }
}

enum DeviceDrill: Hashable {
    case recent(RecentKind)
    case clipboard
}

enum DeviceLook {
    static func symbol(_ phone: PhoneDevice) -> String { phone.platform == "ios" ? "iphone.gen3" : "smartphone" }

    static func status(_ phone: PhoneDevice) -> String {
        let platform = phone.platform == "ios" ? "iPhone" : "Android"
        if phone.online { return "\(platform) · Online" }
        if phone.notSharing { return "\(platform) · Connected, not sharing files" }
        return "\(platform) · \(phone.platform == "ios" ? "Not open" : "Offline")"
    }
}

extension RecentKind {
    var title: String {
        switch self {
        case .photos: return "Photos"
        case .screenshots: return "Screenshots"
        case .downloads: return "Downloads"
        case .documents: return "Documents"
        }
    }

    var symbol: String {
        switch self {
        case .photos: return "photo.on.rectangle"
        case .screenshots: return "camera.viewfinder"
        case .downloads: return "arrow.down.circle"
        case .documents: return "doc.text"
        }
    }

    /// Photos and screenshots show as thumbnails; the rest as rows.
    var isVisual: Bool { self == .photos || self == .screenshots }
}

/// Green when the phone answers right now, an empty ring when it doesn't.
struct OnlineDot: View {
    let online: Bool

    var body: some View {
        Circle()
            .fill(online ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.clear))
            .overlay(Circle().strokeBorder(online ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.tertiary), lineWidth: 1))
            .frame(width: 7, height: 7)
            .accessibilityLabel(online ? "Online" : "Offline")
    }
}

private struct NoticeLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private struct OfflineCard: View {
    let phone: PhoneDevice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "exclamationmark.circle", tint: .orange, size: 28, font: .system(size: 13, weight: .medium))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardBackground()
    }

    private var title: String {
        if phone.notSharing { return "\(phone.name) isn't sharing its files" }
        return phone.platform == "ios" ? "Open Vitals on your iPhone" : "\(phone.name) isn't reachable"
    }

    private var detail: String {
        if phone.notSharing { return "On the phone, open Vitals › Settings › This phone and turn on Let your Mac and other phones browse. This page fills in right away." }
        if phone.platform == "ios" { return "iOS only lets it share while Vitals is open. This page fills in the moment it is." }
        return "Open Vitals on it, or check it's on Wi-Fi or Tailscale. This page fills in the moment it's back."
    }
}

/// Six newest as thumbnails, or four newest as rows. Greyed while the phone is away.
private struct RecentCard: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let kind: RecentKind
    let seeAll: () -> Void
    let pick: (String) -> Void

    var body: some View {
        let recent = pages.page(phone.id).recent[kind]
        let entries = Array((recent?.entries ?? []).prefix(kind.isVisual ? 6 : 4))
        SectionCard(title: kind.title, symbol: kind.symbol) {
            RecentStatus(recent: recent)
            if !entries.isEmpty {
                if kind.isVisual {
                    LazyVGrid(columns: ThumbGrid.columns, spacing: 8) {
                        ForEach(entries) { entry in
                            Button { pick(entry.path) } label: {
                                ThumbTile(image: pages.thumb(phone.id, entry.path), selected: nil)
                            }
                            .buttonStyle(.plain)
                            .help(entry.name)
                        }
                    }
                    .task(id: "\(phone.online)\(entries.map(\.path))") { await pages.loadThumbs(phone.id, paths: entries.map(\.path)) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            EntryRow(entry: entry, asked: pages.page(phone.id).asked.contains(entry.path)) {
                                Button("Get") { Task { await pages.get(phone.id, paths: [entry.path]) } }
                                    .controlSize(.small)
                            }
                            if entry.id != entries.last?.id { Divider() }
                        }
                    }
                }
            }
        } accessory: {
            if recent?.entries.isEmpty == false {
                Button("See all", action: seeAll).buttonStyle(.borderless)
            }
        }
        .opacity(phone.online ? 1 : 0.55)
        .disabled(!phone.online)
    }
}

/// Loading, a phone's error, or "Nothing found" for a kind with no items yet.
private struct RecentStatus: View {
    let recent: DevicesModel.Recent?

    var body: some View {
        if let recent, !recent.entries.isEmpty {
            EmptyView()
        } else if let problem = recent?.problem {
            Text(problem).font(.callout).foregroundStyle(.secondary)
        } else if recent?.loaded == true {
            Text("Nothing found").foregroundStyle(.secondary)
        } else {
            Text("Loading…").foregroundStyle(.secondary)
        }
    }
}

enum ThumbGrid {
    static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
}

struct ThumbTile: View {
    let image: NSImage?
    /// nil hides the selection mark.
    let selected: Bool?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .clipShape(shape)
            .background(shape.fill(.quaternary.opacity(0.35)))
            .overlay(shape.strokeBorder(selected == true ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator.opacity(0.5)), lineWidth: selected == true ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if let selected {
                    SelectionMark(selected: selected)
                        .background(Circle().fill(.background.opacity(selected ? 1 : 0.6)).padding(1))
                        .padding(5)
                }
            }
            .contentShape(shape)
    }
}

struct EntryRow<Trailing: View>: View {
    let entry: PhoneEntry
    let asked: Bool
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            let symbol = DropLook.symbol(name: entry.name)
            IconTile(symbol: symbol, tint: DropLook.tint(symbol: symbol), size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                Text("\(ShareFormat.size(Int(entry.size))) · \(DropLook.when(Date(timeIntervalSince1970: TimeInterval(entry.modifiedAt) / 1000)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if asked {
                Text("Asked").font(.callout).foregroundStyle(.secondary)
            } else {
                trailing
            }
        }
        .padding(.vertical, 6)
    }
}

/// The newest things this phone sent to the clipboard. Works while the phone is away:
/// the Mac keeps them.
private struct ClipsCard: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let seeAll: () -> Void

    var body: some View {
        let page = pages.page(phone.id)
        let rows = Array((page.clips ?? []).prefix(4))
        SectionCard(title: "Clipboard", symbol: "doc.on.clipboard") {
            if rows.isEmpty {
                Text(page.clipsProblem ?? (page.clips == nil ? "Loading…" : "Nothing found")).foregroundStyle(.secondary)
            } else {
                ClipList(phone: phone, rows: rows)
            }
        } accessory: {
            if (page.clips?.count ?? 0) > rows.count {
                Button("See all", action: seeAll).buttonStyle(.borderless)
            }
        }
    }
}

struct ClipList: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let rows: [DevicesModel.ClipRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                ClipRowView(row: row, copied: pages.page(phone.id).copied == row.id) {
                    Task { await pages.copy(phone.id, row) }
                }
                if row.id != rows.last?.id { Divider() }
            }
        }
    }
}

private struct ClipRowView: View {
    let row: DevicesModel.ClipRow
    let copied: Bool
    let copy: () -> Void

    var body: some View {
        let clip = row.item.clip
        HStack(spacing: 10) {
            if let thumb = row.thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                IconTile(symbol: ClipLook.symbol(clip.kind), tint: ClipLook.tint(clip.kind), size: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(ClipLook.preview(clip)).lineLimit(1).truncationMode(.tail)
                Text(ClipLook.detail(clip))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy", action: copy)
                .controlSize(.small)
                .help("Put it on this Mac's clipboard")
        }
        .padding(.vertical, 6)
    }
}

enum ClipLook {
    static func symbol(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .folder: return "folder"
        }
    }

    static func tint(_ kind: ClipKind) -> Color {
        switch kind {
        case .link: return .blue
        case .image: return .pink
        case .folder: return .blue
        case .text, .file: return .gray
        }
    }

    static func preview(_ clip: WireClip) -> String {
        switch clip.kind {
        case .text, .link:
            let text = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return String((text.split(whereSeparator: \.isNewline).first ?? "").prefix(200))
        case .image: return clip.name ?? "Image"
        case .file: return clip.name ?? "File"
        case .folder: return clip.name ?? "Folder"
        }
    }

    static func detail(_ clip: WireClip) -> String {
        let kind: String
        switch clip.kind {
        case .text: kind = "Text"
        case .link: kind = "Link"
        case .image: kind = "Image"
        case .file: kind = "File"
        case .folder: kind = "Folder"
        }
        let size = clip.bytes > 0 && clip.kind != .text && clip.kind != .link ? ShareFormat.size(clip.bytes) : nil
        let when = DropLook.when(Date(timeIntervalSince1970: TimeInterval(clip.at) / 1000))
        return [kind, size, when].compactMap { $0 }.joined(separator: " · ")
    }
}
