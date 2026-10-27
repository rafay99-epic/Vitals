import SwiftUI

/// "‹ Pixel": back to the device page. Escape does the same.
private struct Crumb: View {
    let phone: PhoneDevice
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            Label(phone.name, systemImage: "chevron.left")
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.cancelAction)
    }
}

/// Every item of one kind, newest first: a six-column grid of thumbnails or a list.
/// Select items, then Get asks the phone to send them.
struct RecentDrill: View {
    @Environment(DevicesModel.self) private var pages
    let phone: PhoneDevice
    let kind: RecentKind
    @Binding var selection: Set<String>
    let back: () -> Void

    var body: some View {
        let page = pages.page(phone.id)
        let recent = page.recent[kind] ?? DevicesModel.Recent()
        MetricScroll {
            Crumb(phone: phone, back: back)
            PageHero(value: kind.title, subtitle: subtitle(recent)) {
                if !selection.isEmpty {
                    Button("Deselect") { selection = [] }
                    Button("Get \(selection.count)") {
                        let paths = recent.entries.map(\.path).filter(selection.contains)
                        selection = []
                        Task { await pages.get(phone.id, paths: paths) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!phone.online)
                }
            }
            if let notice = page.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
            if recent.entries.isEmpty {
                Text(recent.problem ?? (recent.loaded ? "Nothing found" : "Loading…")).foregroundStyle(.secondary)
            } else if kind.isVisual {
                grid(recent.entries, asked: page.asked)
            } else {
                list(recent.entries, asked: page.asked)
            }
            if recent.more {
                Button(recent.loading ? "Loading…" : "Show more") {
                    Task { await pages.loadRecent(phone.id, kind, more: true) }
                }
                .disabled(recent.loading || !phone.online)
            }
        }
    }

    private func subtitle(_ recent: DevicesModel.Recent) -> String {
        let count = recent.more ? "\(recent.entries.count)+" : "\(recent.entries.count)"
        let base = "\(count) on \(phone.name) · newest first"
        return selection.isEmpty ? base : "\(selection.count) selected"
    }

    private func grid(_ entries: [PhoneEntry], asked: Set<String>) -> some View {
        LazyVGrid(columns: ThumbGrid.columns, spacing: 8) {
            ForEach(entries) { entry in
                let done = asked.contains(entry.path)
                Button { toggle(entry.path) } label: {
                    ThumbTile(image: pages.thumb(phone.id, entry.path), selected: done ? nil : selection.contains(entry.path))
                        .opacity(done ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(done)
                .help(done ? "\(entry.name) · Asked" : entry.name)
            }
        }
        .task(id: "\(phone.online)\(entries.count)") { await pages.loadThumbs(phone.id, paths: entries.map(\.path)) }
    }

    private func list(_ entries: [PhoneEntry], asked: Set<String>) -> some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                let done = asked.contains(entry.path)
                Button { toggle(entry.path) } label: {
                    EntryRow(entry: entry, asked: done) {
                        SelectionMark(selected: selection.contains(entry.path))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(done)
                if entry.id != entries.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .cardBackground()
    }

    private func toggle(_ path: String) {
        if selection.contains(path) { selection.remove(path) } else { selection.insert(path) }
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
            Crumb(phone: phone, back: back)
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
