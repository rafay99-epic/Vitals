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
/// files. Select, then Transfer.
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
        let entries = folder?.listing?.entries ?? []
        let folders = entries.filter { $0.kind == "folder" }.map { PhoneRoot(label: $0.name, path: $0.path, place: "folder") }
        let files = entries.filter { $0.kind != "folder" }
        let images = files.filter(\.isImage)
        let rest = files.filter { !$0.isImage }
        MetricScroll {
            Crumb(title: trail.dropLast().last?.label ?? phone.name) { open(Array(trail.dropLast())) }
            PageHero(value: here.label, subtitle: subtitle(folder?.listing)) {
                TransferControls(phone: phone, paths: images.map(\.path) + rest.map(\.path), selection: $selection)
            }
            path
            if let notice = page.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            if let problem = folder?.problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
            }
            if let listing = folder?.listing {
                if entries.isEmpty {
                    Text("Empty").foregroundStyle(.secondary)
                }
                if !folders.isEmpty {
                    FolderRows(folders: folders) { open(trail + [$0]) }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .cardBackground()
                }
                if !images.isEmpty {
                    ThumbPicker(phone: phone, entries: images, selection: $selection)
                }
                if !rest.isEmpty {
                    EntryPicker(entries: rest, selection: $selection)
                }
                if listing.total > entries.count {
                    Text("Showing \(entries.count) of \(listing.total)").font(.caption).foregroundStyle(.secondary)
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
    }

    private func subtitle(_ listing: PhoneListing?) -> String {
        if !selection.isEmpty { return "\(selection.count) selected" }
        guard let listing else { return "On \(phone.name)" }
        return "\(listing.total) \(listing.total == 1 ? "item" : "items") on \(phone.name)"
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

/// Folder rows with a chevron. The whole row opens it.
private struct FolderRows: View {
    let folders: [PhoneRoot]
    let open: (PhoneRoot) -> Void

    var body: some View {
        VStack(spacing: 0) {
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
                if folder.id != folders.last?.id { Divider() }
            }
        }
    }
}

private extension PhoneEntry {
    var isImage: Bool { DropLook.symbol(name: name) == "photo" }
}
