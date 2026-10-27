import SwiftUI

/// "‹ Pixel": back up one level. Escape does the same.
struct Crumb: View {
    let title: String
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            Label(title, systemImage: "chevron.left")
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.cancelAction)
    }
}

/// Every item of some kinds, newest first: a six-column grid of thumbnails or a list.
/// Select items, then Transfer sends them to this Mac or another phone.
struct RecentDrill: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let kinds: [RecentKind]
    @Binding var selection: Set<String>
    let back: () -> Void

    var body: some View {
        let page = pages.page(phone.id)
        let recents = kinds.map { page.recent[$0] ?? DevicesModel.Recent() }
        let entries = pages.newest(phone.id, kinds)
        let more = recents.contains(where: \.more)
        MetricScroll {
            Crumb(title: phone.name, back: back)
            PageHero(value: kinds.count == 1 ? kinds[0].title : "Newest images", subtitle: subtitle(entries.count, more: more)) {
                TransferControls(phone: phone, paths: entries.map(\.path), selection: $selection)
            }
            if let notice = page.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                Text(DeviceLook.empty(recents)).foregroundStyle(.secondary)
            } else if kinds.allSatisfy(\.isVisual) {
                ThumbPicker(phone: phone, entries: entries, selection: $selection)
            } else {
                EntryPicker(entries: entries, selection: $selection)
            }
            if more {
                Button(recents.contains(where: \.loading) ? "Loading…" : "Show more") {
                    Task {
                        for kind in kinds where page.recent[kind]?.more == true {
                            await pages.loadRecent(phone.id, kind, more: true)
                        }
                    }
                }
                .disabled(recents.contains(where: \.loading) || !phone.online)
            }
        }
    }

    private func subtitle(_ count: Int, more: Bool) -> String {
        selection.isEmpty ? "\(count)\(more ? "+" : "") on \(phone.name) · newest first" : "\(selection.count) selected"
    }
}

/// Deselect and Transfer for a drill's selection. Transfer offers this Mac and every other
/// phone, never the one the files are on.
struct TransferControls: View {
    @Environment(DevicesModel.self) private var pages
    @Environment(RemoteModel.self) private var remote
    let phone: PhoneDevice
    /// The drill's items in order, so a transfer keeps it.
    let paths: [String]
    @Binding var selection: Set<String>

    var body: some View {
        if !selection.isEmpty {
            Button("Deselect") { selection = [] }
            Menu("Transfer \(selection.count)") {
                Button { send(to: nil) } label: {
                    Text("This Mac")
                    Text(ShareFormat.folder(remote.share.folder))
                }
                ForEach(pages.destinations(from: phone.id)) { other in
                    Button { send(to: other) } label: {
                        Text(other.name)
                        Text(DeviceLook.status(other))
                    }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(!phone.online)
        }
    }

    private func send(to target: PhoneDevice?) {
        let picked = paths.filter(selection.contains)
        selection = []
        Task { await pages.transfer(phone.id, paths: picked, to: target) }
    }
}

/// Selectable thumbnails in the fixed six-column grid.
struct ThumbPicker: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let entries: [PhoneEntry]
    @Binding var selection: Set<String>

    var body: some View {
        LazyVGrid(columns: ThumbGrid.columns, spacing: 8) {
            ForEach(entries) { entry in
                Button { selection.formSymmetricDifference([entry.path]) } label: {
                    ThumbTile(image: pages.thumb(phone.id, entry.path), selected: selection.contains(entry.path))
                }
                .buttonStyle(.plain)
                .help(entry.name)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(selection.contains(entry.path) ? .isSelected : [])
            }
        }
        .task(id: "\(phone.online)\(entries.count)\(entries.first?.path ?? "")") { await pages.loadThumbs(phone.id, paths: entries.map(\.path)) }
    }
}

/// Selectable file rows in one card.
struct EntryPicker: View {
    let entries: [PhoneEntry]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                Button { selection.formSymmetricDifference([entry.path]) } label: {
                    EntryRow(entry: entry) {
                        SelectionMark(selected: selection.contains(entry.path))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if entry.id != entries.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .cardBackground()
    }
}

/// Everything this phone sent to the clipboard, newest first. Copy puts one on the Mac clipboard.
struct ClipsDrill: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let back: () -> Void

    var body: some View {
        let page = pages.page(phone.id)
        let rows = page.clips ?? []
        MetricScroll {
            Crumb(title: phone.name, back: back)
            PageHero(value: "Clipboard", subtitle: "\(rows.count) from \(phone.name) · newest first") { EmptyView() }
            if let notice = page.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text(page.clipsProblem ?? "Nothing found").foregroundStyle(.secondary)
            } else {
                ClipList(phone: phone, rows: rows)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .cardBackground()
            }
        }
    }
}
