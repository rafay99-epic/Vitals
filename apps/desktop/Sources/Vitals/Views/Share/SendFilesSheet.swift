import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SendFilesSheet: View {
    @Environment(ShareModel.self) private var share
    @State private var targeted = false

    var body: some View {
        let draft = share.draft
        let items = draft?.items ?? []
        VStack(alignment: .leading, spacing: 14) {
            Text("Send Files")
                .font(.system(size: 15, weight: .semibold))
            dropZone(items)
            if let error = draft?.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Text("To")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if share.phones.isEmpty {
                Text("No phone can get files. Turn on Files for a phone in Devices.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                PhoneChoices(phones: share.phones, selection: selection, lastUsed: share.lastPhone)
            }
            HStack {
                Text(items.isEmpty ? "Nothing added" : "\(items.count == 1 ? "1 item" : "\(items.count) items") · \(ShareFormat.size(items.reduce(0) { $0 + $1.bytes }))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel") { share.draft = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Send") { share.sendDraft() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(items.isEmpty || (draft?.adding ?? 0) > 0 || !share.phones.contains { draft?.to.contains($0.id) == true })
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var selection: Binding<Set<String>> {
        Binding(get: { share.draft?.to ?? [] }, set: { share.draft?.to = $0 })
    }

    private func dropZone(_ items: [DropFiles.Item]) -> some View {
        VStack(spacing: 8) {
            if items.isEmpty {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop files or folders")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            AppIconView(url: item.url, size: 18)
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(item.isFolder ? "\(ShareFormat.files(item.files.count)) · \(ShareFormat.size(item.bytes))" : ShareFormat.size(item.bytes))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button { share.draft?.items.removeAll { $0.id == item.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            if (share.draft?.adding ?? 0) > 0 {
                ProgressView().controlSize(.small)
            }
            Button("Choose…") { choose() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(targeted ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.3)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(targeted ? AnyShapeStyle(Color.accentColor.opacity(0.7)) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: 1, dash: items.isEmpty ? [5, 4] : []))
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task { @MainActor in share.addToDraft(await Self.urls(from: providers)) }
            return true
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        share.addToDraft(panel.urls)
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url, url.isFileURL { urls.append(url) }
        }
        return urls
    }
}
