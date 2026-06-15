import SwiftUI
import AppKit

/// The Login Items tab: everything that launches itself on this Mac — your own
/// login agents (toggleable), and the system-wide agents/daemons (read-only).
/// Reading is liberal; the only write is reversibly disabling one of your own
/// non-Apple agents, behind a confirmation.
struct LoginItemsView: View {
    @ObservedObject var model: LoginItemsModel
    let isActive: Bool
    @State private var pendingDisable: LaunchItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.loaded && model.loading {
                    LoadingStateView(title: "Reading login items",
                                     message: "Looking at what launches at startup.")
                } else if model.items.isEmpty {
                    EmptyStateView(symbol: "power", tint: .teal, title: "Nothing auto-starts",
                                   message: "No login agents or startup daemons were found on this Mac.") { EmptyView() }
                } else {
                    intro
                    if !model.userItems.isEmpty {
                        LaunchSection(title: "Yours", symbol: "person.crop.circle", tint: .blue,
                                      subtitle: "Login agents you installed — turn off what you don't want at startup.",
                                      items: model.userItems, model: model, pendingDisable: $pendingDisable)
                    }
                    if !model.systemItems.isEmpty {
                        LaunchSection(title: "System", symbol: "gearshape.2", tint: .secondary,
                                      subtitle: "Installed system-wide or by macOS. Shown read-only — disabling these needs admin and can affect the OS.",
                                      items: model.systemItems, model: model, pendingDisable: $pendingDisable)
                    }
                }
            }
            .padding(20)
        }
        .task(id: isActive) { if isActive { await model.loadIfNeeded() } }
        .confirmationDialog(
            "Disable “\(pendingDisable?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingDisable != nil }, set: { if !$0 { pendingDisable = nil } }),
            presenting: pendingDisable
        ) { item in
            Button("Disable", role: .destructive) {
                Task { await model.setDisabled(true, item) }
                pendingDisable = nil
            }
            Button("Cancel", role: .cancel) { pendingDisable = nil }
        } message: { item in
            Text("“\(item.displayName)” won't launch at login and will be stopped now. You can re-enable it here anytime.")
        }
    }

    private var intro: some View {
        HStack(spacing: 10) {
            Text("\(model.items.count) launch items")
                .font(.callout.weight(.medium))
            Spacer()
            Button {
                Task { await model.reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(model.loading)
        }
        .padding(.horizontal, 4)
    }
}

private struct LaunchSection: View {
    let title: String
    let symbol: String
    let tint: Color
    let subtitle: String
    let items: [LaunchItem]
    @ObservedObject var model: LoginItemsModel
    @Binding var pendingDisable: LaunchItem?

    var body: some View {
        SectionCard(title: title, symbol: symbol) {
            VStack(alignment: .leading, spacing: 0) {
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(items) { item in
                    LaunchItemRow(item: item, model: model, pendingDisable: $pendingDisable)
                    if item.id != items.last?.id { Divider().opacity(0.5) }
                }
            }
        }
    }
}

private struct LaunchItemRow: View {
    let item: LaunchItem
    @ObservedObject var model: LoginItemsModel
    @Binding var pendingDisable: LaunchItem?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .systemDaemon ? "gearshape.2.fill" : "arrow.right.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(item.disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.teal))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.teal.opacity(item.disabled ? 0.06 : 0.14)))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(item.disabled ? .secondary : .primary)
                    if item.runAtLoad {
                        Text("at login").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary.opacity(0.5)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.program ?? item.label)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if item.disabled {
                Text("Disabled").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.plistPath])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Reveal in Finder")

            if item.canToggle {
                if item.disabled {
                    Button("Enable") { Task { await model.setDisabled(false, item) } }
                        .controlSize(.small)
                } else {
                    Button("Disable") { pendingDisable = item }
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 7)
    }
}
