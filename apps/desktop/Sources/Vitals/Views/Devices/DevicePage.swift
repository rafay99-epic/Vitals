import SwiftUI

/// One phone's page under Devices in the sidebar: a tile per kind of file, its newest images,
/// its folders, then what it sent to the clipboard. Tiles, "See all" and folders drill in
/// inline, with a crumb back, never a second navigation level.
struct DevicePage: View {
    @Environment(DevicesModel.self) private var pages
    let deviceId: String?
    @State private var drill: DeviceDrill?
    @State private var selection: Set<String> = []

    var body: some View {
        if let deviceId, let phone = pages.phone(deviceId) {
            Group {
                switch drill {
                case let .recent(kinds):
                    RecentDrill(phone: phone, kinds: kinds, selection: $selection) { open(nil) }
                case let .folder(trail):
                    FolderDrill(phone: phone, trail: trail, selection: $selection) { open($0.isEmpty ? nil : .folder($0)) }
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
            if phone.online || !page.recent.isEmpty {
                KindTiles(phone: phone) { open(.recent([$0])) }
                NewestImages(phone: phone, seeAll: { open(.recent(RecentKind.images)) }, pick: { path in
                    selection = [path]
                    drill = .recent(RecentKind.images)
                })
            }
            if phone.online || page.roots != nil {
                PhoneFilesCard(phone: phone) { open(.folder([$0])) }
            }
            ClipsCard(phone: phone) { open(.clipboard) }
        }
    }

    private func open(_ next: DeviceDrill?) {
        selection = []
        drill = next
    }
}

enum DeviceDrill: Equatable {
    case recent([RecentKind])
    /// The folders opened so far, outermost first.
    case folder([PhoneRoot])
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

    private static let ageFormat: RelativeDateTimeFormatter = {
        let format = RelativeDateTimeFormatter()
        format.unitsStyle = .short
        return format
    }()

    /// "2 min. ago". A phone clock a little ahead of the Mac's reads as now, not the future.
    static func age(_ entry: PhoneEntry) -> String {
        let now = Date.now
        return ageFormat.localizedString(for: min(Date(timeIntervalSince1970: TimeInterval(entry.modifiedAt) / 1000), now), relativeTo: now)
    }

    /// What a list with no items says: a phone's error, "Nothing found" once every kind loaded,
    /// else "Loading…".
    static func empty(_ recents: [DevicesModel.Recent]) -> String {
        if let problem = recents.lazy.compactMap(\.problem).first { return problem }
        return !recents.isEmpty && recents.allSatisfy(\.loaded) ? "Nothing found" : "Loading…"
    }
}

extension RecentKind {
    /// Screenshots and photos, merged in "Newest images".
    static let images: [RecentKind] = [.screenshots, .photos]

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

/// Screenshots, Photos, Downloads, Documents in one fixed row: each with its newest item and
/// how old it is. Greyed while the phone is away.
private struct KindTiles: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let open: (RecentKind) -> Void

    private static let kinds: [RecentKind] = [.screenshots, .photos, .downloads, .documents]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        let recent = pages.page(phone.id).recent
        let newest = Self.kinds.compactMap { recent[$0]?.entries.first?.path }
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(Self.kinds, id: \.self) { kind in
                Button { open(kind) } label: {
                    KindTile(phone: phone, kind: kind, recent: recent[kind] ?? DevicesModel.Recent())
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: "\(phone.online)\(newest)") { await pages.loadThumbs(phone.id, paths: newest) }
        .opacity(phone.online ? 1 : 0.55)
        .disabled(!phone.online)
    }
}

private struct KindTile: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let kind: RecentKind
    let recent: DevicesModel.Recent

    var body: some View {
        let newest = recent.entries.first
        VStack(alignment: .leading, spacing: 8) {
            preview(newest)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.body.weight(.medium))
                Text(newest.map(DeviceLook.age) ?? DeviceLook.empty([recent]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(10)
        .cardBackground()
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help(newest?.name ?? kind.title)
    }

    @ViewBuilder private func preview(_ newest: PhoneEntry?) -> some View {
        if let newest, let image = pages.thumb(phone.id, newest.path) {
            Color.clear.overlay { Image(nsImage: image).resizable().scaledToFill() }
        } else {
            let symbol = newest.map { DropLook.symbol(name: $0.name) } ?? kind.symbol
            Rectangle()
                .fill(.quaternary.opacity(0.35))
                .overlay { IconTile(symbol: symbol, tint: newest == nil ? .secondary : DropLook.tint(symbol: symbol), size: 28, font: .system(size: 13, weight: .medium)) }
        }
    }
}

/// Screenshots and photos merged, newest first, in one row of thumbnails.
private struct NewestImages: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let seeAll: () -> Void
    let pick: (String) -> Void

    var body: some View {
        let all = pages.newest(phone.id, RecentKind.images)
        let entries = Array(all.prefix(ThumbGrid.count))
        SectionCard(title: "Newest images", symbol: "photo.on.rectangle") {
            if entries.isEmpty {
                let recent = pages.page(phone.id).recent
                Text(DeviceLook.empty(RecentKind.images.map { recent[$0] ?? DevicesModel.Recent() })).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: ThumbGrid.columns, spacing: 8) {
                    ForEach(entries) { entry in
                        Button { pick(entry.path) } label: {
                            ThumbTile(image: pages.thumb(phone.id, entry.path), selected: nil)
                        }
                        .buttonStyle(.plain)
                        .help(entry.name)
                        .accessibilityLabel(entry.name)
                    }
                }
                .task(id: "\(phone.online)\(entries.map(\.path))") { await pages.loadThumbs(phone.id, paths: entries.map(\.path)) }
            }
        } accessory: {
            if !all.isEmpty {
                Button("See all", action: seeAll).buttonStyle(.borderless)
            }
        }
        .opacity(phone.online ? 1 : 0.55)
        .disabled(!phone.online)
    }
}

enum ThumbGrid {
    static let count = 6
    static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
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
            trailing
        }
        .padding(.vertical, 6)
    }
}

/// The newest things this phone sent to the clipboard, kept apart from its files. Works while
/// the phone is away: the Mac keeps them.
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
