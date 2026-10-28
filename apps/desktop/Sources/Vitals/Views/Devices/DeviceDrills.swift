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
/// Select items, then Transfer sends them to this Mac or another phone; double-click or Space
/// previews them.
struct RecentDrill: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let kinds: [RecentKind]
    @Binding var selection: Set<String>
    let back: () -> Void

    var body: some View {
        let page = pages.page(phone.id)
        let recents = kinds.map { page.recent[$0] ?? DevicesModel.Recent() }
        let items = pages.newest(phone.id, kinds)
        let more = recents.contains(where: \.more)
        MetricScroll {
            Crumb(title: phone.name, back: back)
            PageHero(value: kinds.count == 1 ? kinds[0].title : "Newest images", subtitle: subtitle(items.count, more: more)) {
                TransferControls(phone: phone, items: items, selection: $selection)
            }
            if let notice = page.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            PreviewLine(phone: phone)
            if items.isEmpty {
                Text(DeviceLook.empty(recents)).foregroundStyle(.secondary)
            } else if kinds.allSatisfy(\.isVisual) {
                ThumbPicker(phone: phone, items: items, selection: $selection)
            } else {
                EntryPicker(phone: phone, items: items, selection: $selection)
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
        .spaceToPreview { pages.preview(phone.id, items.filter { selection.contains($0.path) }) }
    }

    private func subtitle(_ count: Int, more: Bool) -> String {
        selection.isEmpty ? "\(count)\(more ? "+" : "") on \(phone.name) · newest first" : "\(selection.count) selected"
    }
}

/// Preview, Deselect and Transfer for a drill's selection. Transfer offers this Mac and every
/// other phone, never the one the files are on.
struct TransferControls: View {
    @Environment(DevicesModel.self) private var pages
    @Environment(RemoteModel.self) private var remote
    let phone: PhoneDevice
    /// The drill's items in order, so a preview or transfer keeps it.
    let items: [DevicesModel.Item]
    @Binding var selection: Set<String>

    var body: some View {
        if !selection.isEmpty {
            Button("Preview") { pages.preview(phone.id, picked) }
                .disabled(!phone.online)
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

    private var picked: [DevicesModel.Item] { items.filter { selection.contains($0.path) } }

    private func send(to target: PhoneDevice?) {
        let paths = picked.map(\.path)
        selection = []
        Task { await pages.transfer(phone.id, paths: paths, to: target) }
    }
}

/// Selectable thumbnails in the fixed six-column grid. `end` runs when the last one comes on
/// screen, to load the next page.
struct ThumbPicker: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let items: [DevicesModel.Item]
    @Binding var selection: Set<String>
    var end: (() -> Void)?

    var body: some View {
        LazyVGrid(columns: ThumbGrid.columns, spacing: 8) {
            ForEach(items) { item in
                ThumbCell(device: phone.id, item: item, selected: selection.contains(item.path)) {
                    selection.formSymmetricDifference([item.path])
                } open: {
                    selection = [item.path]
                    pages.preview(phone.id, [item])
                }
                .equatable()
                .onAppear { if item.id == items.last?.id { end?() } }
            }
        }
    }
}

/// Click selects, double-click previews. Equal cells skip their body when the grid redraws.
private struct ThumbCell: View, Equatable {
    let device: String
    let item: DevicesModel.Item
    let selected: Bool
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        Button(action: toggle) {
            ThumbTile(device: device, path: item.path, selected: selected)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded(open))
        .contextMenu { Button("Preview", action: open) }
        .help(item.name)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.device == rhs.device && lhs.selected == rhs.selected && lhs.item == rhs.item
    }
}

/// Selectable file rows in one card. `end` runs when the last one comes on screen.
struct EntryPicker: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let items: [DevicesModel.Item]
    @Binding var selection: Set<String>
    var end: (() -> Void)?

    var body: some View {
        let last = items.last?.id
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                EntryCell(item: item, selected: selection.contains(item.path), divider: item.id != last) {
                    selection.formSymmetricDifference([item.path])
                } open: {
                    selection = [item.path]
                    pages.preview(phone.id, [item])
                }
                .equatable()
                .onAppear { if item.id == last { end?() } }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .cardBackground()
    }
}

/// Click selects, double-click previews.
private struct EntryCell: View, Equatable {
    let item: DevicesModel.Item
    let selected: Bool
    let divider: Bool
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                EntryRow(item: item) {
                    SelectionMark(selected: selected)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded(open))
            .contextMenu { Button("Preview", action: open) }
                if divider { Divider() }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selected == rhs.selected && lhs.divider == rhs.divider && lhs.item == rhs.item
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
