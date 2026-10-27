import SwiftUI

/// A phone's whole shared storage, folder by folder. Get asks the phone to send a file.
struct PhoneFilesCard: View {
    @Environment(RemoteModel.self) private var remote
    let device: PhoneDevice
    @State private var roots: [PhoneRoot] = []
    @State private var trail: [PhoneRoot] = []
    @State private var listing: PhoneListing?
    @State private var problem: String?
    @State private var getting: Set<String> = []

    var body: some View {
        SectionCard(title: "All files", symbol: "folder") {
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.orange)
            }
            browser
        }
        .task(id: device.online) {
            guard device.online, roots.isEmpty else { return }
            do { roots = try await remote.phoneRoots(device.deviceId) } catch { problem = message(error) }
        }
    }

    @ViewBuilder private var browser: some View {
        if !trail.isEmpty {
            HStack(spacing: 6) {
                Button { back() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(trail.map(\.label).joined(separator: " › "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        if trail.isEmpty {
            ForEach(roots) { root in
                row(title: root.label, symbol: "folder", detail: nil) { open(root) }
            }
        } else if let listing {
            if listing.entries.isEmpty {
                Text("Empty").foregroundStyle(.secondary)
            }
            ForEach(listing.entries) { entry in
                if entry.kind == "folder" {
                    row(title: entry.name, symbol: "folder", detail: nil) { open(PhoneRoot(label: entry.name, path: entry.path, place: "folder")) }
                } else {
                    HStack {
                        Image(systemName: "doc").foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).lineLimit(1).truncationMode(.middle)
                            Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(getting.contains(entry.path) ? "Asked" : "Get") { get(entry) }
                            .controlSize(.small)
                            .disabled(getting.contains(entry.path) || !device.online)
                    }
                }
            }
            if listing.total > listing.entries.count {
                Text("Showing \(listing.entries.count) of \(listing.total)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(title: String, symbol: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).foregroundStyle(.blue).frame(width: 18)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!device.online)
    }

    private func open(_ root: PhoneRoot) {
        Task {
            do {
                let next = try await remote.phoneList(device.deviceId, path: root.path)
                trail.append(root)
                listing = next
                problem = nil
            } catch { problem = message(error) }
        }
    }

    private func back() {
        trail.removeLast()
        guard let current = trail.last else {
            listing = nil
            return
        }
        Task { listing = try? await remote.phoneList(device.deviceId, path: current.path) }
    }

    private func get(_ entry: PhoneEntry) {
        getting.insert(entry.path)
        Task {
            do { _ = try await remote.pullFromPhone(device.deviceId, paths: [entry.path]) } catch {
                getting.remove(entry.path)
                problem = message(error)
            }
        }
    }

    private func message(_ error: Error) -> String {
        (error as? RemoteModel.AdminFailure)?.message ?? "That phone didn't answer"
    }
}
