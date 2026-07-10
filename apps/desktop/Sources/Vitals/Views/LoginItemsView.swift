import SwiftUI
import AppKit

/// The Login Items tab: everything that launches itself on this Mac — your own
/// login agents, system agents, and root daemons. Reading is liberal; writes
/// (disable / remove) are confirmed and, where possible, reversible. Apple's own
/// items are never modified, and removing your own agents goes to the Trash.
struct LoginItemsView: View {
    @ObservedObject var model: LoginItemsModel
    let isActive: Bool
    @State private var pending: PendingAction?

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
                        LaunchSection(title: "Yours", symbol: "person.crop.circle",
                                      subtitle: "Login agents you installed. Disable to stop them launching, or remove to the Trash (recoverable).",
                                      items: model.userItems, model: model, pending: $pending)
                    }
                    if !model.systemItems.isEmpty {
                        LaunchSection(title: "System", symbol: "gearshape.2",
                                      subtitle: "Installed system-wide or by macOS. You can disable or remove non-Apple ones (with an admin prompt); Apple's are read-only.",
                                      items: model.systemItems, model: model, pending: $pending)
                    }
                }
            }
            .padding(20)
        }
        .task(id: isActive) { if isActive { await model.loadIfNeeded() } }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { action in
            confirmButton(action)
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { action in
            Text(dialogMessage(action))
        }
    }

    private var intro: some View {
        HStack(spacing: 8) {
            Text("\(model.items.count) launch items").font(.callout.weight(.medium))
            if let bytes = model.userFootprintBytes {
                Text("·").foregroundStyle(.tertiary)
                Text("\(formatMemory(bytes)) in use")
                    .font(.system(.callout, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
                    .help("Live memory footprint of your running login agents right now")
            }
            Spacer()
            Button { Task { await model.reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .controlSize(.small)
                .disabled(model.loading)
        }
        .padding(.horizontal, 4)
    }

    private var dialogTitle: String {
        guard let pending else { return "" }
        switch pending {
        case .disable(let item): return "Disable “\(item.displayName)”?"
        case .remove(let item):  return item.removeNeedsAdmin ? "Remove “\(item.displayName)”?" : "Move “\(item.displayName)” to Trash?"
        }
    }

    @ViewBuilder
    private func confirmButton(_ action: PendingAction) -> some View {
        switch action {
        case .disable(let item):
            Button("Disable", role: .destructive) { run { await model.setDisabled(true, item) } }
        case .remove(let item):
            Button(item.removeNeedsAdmin ? "Remove" : "Move to Trash", role: .destructive) { run { await model.remove(item) } }
        }
    }

    private func dialogMessage(_ action: PendingAction) -> String {
        switch action {
        case .disable(let item):
            let base = "“\(item.displayName)” won't launch at login and will be stopped now. You can re-enable it here anytime."
            return item.disableNeedsAdmin ? base + " Requires an administrator password." : base
        case .remove(let item):
            return item.removeNeedsAdmin
                ? "Its launch settings will be removed (administrator password required). Unlike disabling, this is permanent."
                : "Its launch settings move to the Trash, so you can put them back if needed."
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        Task { await work() }
        pending = nil
    }
}

/// A disable/remove awaiting confirmation.
private enum PendingAction: Identifiable {
    case disable(LaunchItem)
    case remove(LaunchItem)

    var item: LaunchItem {
        switch self {
        case .disable(let item), .remove(let item): return item
        }
    }
    var id: String {
        switch self {
        case .disable(let item): return "disable-" + item.id
        case .remove(let item):  return "remove-" + item.id
        }
    }
}

private struct LaunchSection: View {
    let title: String
    let symbol: String
    let subtitle: String
    let items: [LaunchItem]
    @ObservedObject var model: LoginItemsModel
    @Binding var pending: PendingAction?

    var body: some View {
        SectionCard(title: title, symbol: symbol) {
            VStack(alignment: .leading, spacing: 0) {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
                ForEach(items) { item in
                    LaunchItemRow(item: item, model: model, pending: $pending)
                    if item.id != items.last?.id { Divider().opacity(0.5) }
                }
            }
        }
    }
}

private struct LaunchItemRow: View {
    let item: LaunchItem
    @ObservedObject var model: LoginItemsModel
    @Binding var pending: PendingAction?

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
                        .font(.callout.weight(.medium)).lineLimit(1)
                        .foregroundStyle(item.disabled ? .secondary : .primary)
                    if item.runAtLoad {
                        Text("at login").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary.opacity(0.5)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.program ?? item.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 8)

            impactMetric
                .fixedSize()

            if item.disabled {
                Text("Disabled").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }

            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plistPath]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless).controlSize(.small).help("Reveal in Finder")

            if item.isActionable {
                Menu {
                    if item.disabled {
                        Button { Task { await model.setDisabled(false, item) } } label: { Label("Enable", systemImage: "play.circle") }
                    } else {
                        Button { pending = .disable(item) } label: { Label("Disable", systemImage: "pause.circle") }
                    }
                    Button(role: .destructive) { pending = .remove(item) } label: { Label("Remove…", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help("Manage")
            }
        }
        .padding(.vertical, 7)
    }

    /// The live resource cost — a real footprint + impact tier for a running user
    /// agent, or an honest "Not running" / "Running". System items (`notMeasured`)
    /// show nothing rather than a fabricated figure. A disabled item won't be
    /// running, so its state naturally reads idle.
    @ViewBuilder
    private var impactMetric: some View {
        switch model.impact[item.id] ?? .notMeasured {
        case .running(let cost):
            HStack(spacing: 6) {
                Text(formatMemory(cost.memoryBytes))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
                    .help("\(formatMemory(cost.memoryBytes)) · \(cpuText(cost.cpuSeconds)) of CPU time since it launched")
                ImpactCapsule(level: StartupImpact.level(.running(cost)))
            }
        case .runningUnreadable:
            Text("Running").font(.caption).foregroundStyle(.secondary)
        case .idle:
            Text("Not running").font(.caption).foregroundStyle(.tertiary)
        case .notMeasured:
            EmptyView()
        }
    }
}

/// A small High / Medium / Low impact badge. Higher footprint reads warmer — the
/// standing cost of keeping the item resident. Idle/unknown states show nothing.
private struct ImpactCapsule: View {
    let level: StartupImpact.Level

    var body: some View {
        if let descriptor {
            Text(descriptor.label)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(descriptor.tint.opacity(0.16)))
                .foregroundStyle(descriptor.tint)
        }
    }

    private var descriptor: (label: String, tint: Color)? {
        switch level {
        case .high:   return ("High", .orange)
        case .medium: return ("Medium", .yellow)
        case .low:    return ("Low", .green)
        case .idle, .unknown: return nil
        }
    }
}

/// Physical-memory footprint, formatted the way Activity Monitor's "Memory" is.
private func formatMemory(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}

/// Cumulative CPU time as a compact, honest duration.
private func cpuText(_ seconds: Double) -> String {
    if seconds < 1 { return "<1s" }
    if seconds < 60 { return "\(Int(seconds))s" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    let hours = Int(seconds / 3600)
    let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
    return "\(hours)h \(minutes)m"
}
