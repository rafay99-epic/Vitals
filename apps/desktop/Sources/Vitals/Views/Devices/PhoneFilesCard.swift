import SwiftUI

/// A phone's shared folders. Opening one drills in on the device page.
struct PhoneFilesCard: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let open: (PhoneRoot) -> Void

    var body: some View {
        let page = pages.page(phone.id)
        SectionCard(title: "Folders", symbol: "folder") {
            if let roots = page.roots, !roots.isEmpty {
                FolderRows(folders: roots, open: open)
            } else {
                Text(page.rootsProblem ?? (page.roots == nil ? "Loading…" : "Nothing found")).foregroundStyle(.secondary)
            }
        }
        .opacity(phone.online ? 1 : 0.55)
        .disabled(!phone.online)
    }
}

/// One folder on a phone, with its path: folders first, then images in the fixed grid, then
/// files. Loads a page at a time as the end comes on screen. Select, then Transfer; double-click
/// or Space previews.
struct FolderDrill: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    /// Never empty: the device page shows the roots.
    let trail: [PhoneRoot]
    @Binding var selection: Set<String>
    let open: ([PhoneRoot]) -> Void

    var body: some View {
        let page = pages.page(phone.id)
        let here = trail[trail.count - 1]
        let folder = page.folders[here.path]
        let items = (folder?.images ?? []) + (folder?.files ?? [])
        MetricScroll {
            Crumb(title: trail.dropLast().last?.label ?? phone.name) { open(Array(trail.dropLast())) }
            PageHero(value: here.label, subtitle: subtitle(folder)) {
                TransferControls(phone: phone, items: items, selection: $selection)
            }
            path
            if let notice = page.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            PreviewLine(phone: phone)
            if let problem = folder?.problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
            }
            if let folder, let total = folder.total {
                if total == 0 {
                    Text("Empty").foregroundStyle(.secondary)
                }
                if !folder.folders.isEmpty {
                    FolderRows(folders: folder.folders, open: { open(trail + [$0]) }, end: folder.images.isEmpty && folder.files.isEmpty ? { more(here, folder) } : nil)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .cardBackground()
                }
                if !folder.images.isEmpty {
                    ThumbPicker(phone: phone, items: folder.images, selection: $selection) { more(here, folder) }
                }
                if !folder.files.isEmpty {
                    EntryPicker(phone: phone, items: folder.files, selection: $selection) { more(here, folder) }
                }
                if folder.more {
                    Text("Showing \(folder.loaded) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .task(id: folder.loaded) { more(here, folder) }
                }
            } else if folder?.problem == nil {
                Text("Loading…").foregroundStyle(.secondary)
            }
        }
        .id(here.path)
        .task(id: "\(phone.online)\(here.path)") {
            guard phone.online else { return }
            await pages.loadFolder(phone.id, path: here.path)
        }
        .spaceToPreview { pages.preview(phone.id, items.filter { selection.contains($0.path) }) }
    }

    private func more(_ here: PhoneRoot, _ folder: DevicesModel.Folder) {
        guard folder.more, !folder.loading, phone.online else { return }
        Task { await pages.loadFolder(phone.id, path: here.path, more: true) }
    }

    private func subtitle(_ folder: DevicesModel.Folder?) -> String {
        if !selection.isEmpty { return "\(selection.count) selected" }
        guard let total = folder?.total else { return "On \(phone.name)" }
        return "\(total) \(total == 1 ? "item" : "items") on \(phone.name)"
    }

    /// "Pixel 9 › Download › Camera": every part but the last jumps back to it.
    private var path: some View {
        HStack(spacing: 4) {
            Button(phone.name) { open([]) }
                .buttonStyle(.borderless)
            ForEach(trail.indices, id: \.self) { index in
                Text("›").foregroundStyle(.tertiary)
                if index == trail.count - 1 {
                    Text(trail[index].label)
                } else {
                    Button(trail[index].label) { open(Array(trail.prefix(index + 1))) }
                        .buttonStyle(.borderless)
                }
            }
        }
        .font(.callout)
        .lineLimit(1)
    }
}

/// Folder rows with a chevron. The whole row opens it. `end` runs when the last one comes on screen.
private struct FolderRows: View {
    let folders: [PhoneRoot]
    let open: (PhoneRoot) -> Void
    var end: (() -> Void)?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(folders) { folder in
                Button { open(folder) } label: {
                    HStack(spacing: 10) {
                        IconTile(symbol: "folder", tint: .blue, size: 26)
                        Text(folder.label).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear { if folder.id == folders.last?.id { end?() } }
                if folder.id != folders.last?.id { Divider() }
            }
        }
    }
}
