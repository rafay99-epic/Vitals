import SwiftUI

/// The Cleanup tab: categories of regenerable data as selectable cards,
/// cleaned on explicit confirmation. Caches and logs are deleted (trashing
/// them would free nothing); the Trash category empties permanently and the
/// confirmation says so.
struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    grid
                }
                .padding(20)
            }
            Divider()
                .opacity(0.5)
            footer
        }
        .onAppear { if model.categories.isEmpty { model.refresh() } }
        .confirmationDialog(
            "Clean \(formatBytes(model.selectedBytes))?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Clean", role: .destructive) { model.clean() }
        } message: {
            Text(confirmationMessage)
        }
        .alert(
            "Cleanup finished",
            isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.dismissResult() } }),
            presenting: model.lastResult
        ) { _ in
            Button("OK") { model.dismissResult() }
        } message: { result in
            if result.failures.isEmpty {
                Text("Freed \(formatBytes(result.freedBytes)) (\(result.removedItems) items).")
            } else {
                Text("Freed \(formatBytes(result.freedBytes)). \(result.failures.count) items couldn't be removed (in use or protected).")
            }
        }
    }

    private var confirmationMessage: String {
        var lines = "Selected caches and logs are deleted — apps rebuild them automatically."
        if model.selected.contains(.trash) {
            lines += " Emptying the Trash is permanent."
        }
        return lines
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(heroValue)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(heroSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                model.refresh()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .disabled(model.isScanning)
            .help("Scan again")
        }
    }

    private var heroValue: String {
        if model.totalBytes > 0 { return formatBytes(model.totalBytes) }
        return model.isScanning ? "Scanning…" : "All clean"
    }

    private var heroSubtitle: String {
        let populated = model.categories.filter { !$0.items.isEmpty }.count
        if model.totalBytes > 0 {
            return "reclaimable across \(populated) categories — all of it regenerable"
        }
        return model.isScanning ? "measuring caches, logs, and the Trash" : "nothing worth reclaiming right now"
    }

    // MARK: Category grid

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(model.categories) { category in
                CategoryCard(
                    category: category,
                    isScanning: model.isScanning,
                    isSelected: model.selected.contains(category.kind)
                ) {
                    if model.selected.contains(category.kind) {
                        model.selected.remove(category.kind)
                    } else {
                        model.selected.insert(category.kind)
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Only regenerable data — documents and settings are never touched.", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !model.selected.isEmpty {
                Text("\(model.selected.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                confirming = true
            } label: {
                if model.isCleaning {
                    Label("Cleaning…", systemImage: "sparkles")
                } else {
                    Label(
                        model.selectedBytes > 0 ? "Clean \(formatBytes(model.selectedBytes))" : "Clean",
                        systemImage: "sparkles"
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selected.isEmpty || model.isCleaning || model.selectedBytes == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Category card

private extension CleanupCategory.Kind {
    var tint: Color {
        switch self {
        case .xcode: return .blue
        case .devCaches: return .orange
        case .homebrew: return .yellow
        case .appCaches: return .purple
        case .logs: return .teal
        case .trash: return .red
        }
    }
}

private struct CategoryCard: View {
    let category: CleanupCategory
    let isScanning: Bool
    let isSelected: Bool
    let toggle: () -> Void

    private var isEmpty: Bool { category.items.isEmpty }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: category.kind.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(category.kind.tint)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(category.kind.tint.opacity(0.14))
                        )
                    Text(category.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                }

                Text(category.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)

                HStack(alignment: .firstTextBaseline) {
                    if isEmpty {
                        Text("Nothing found")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else if category.sizeBytes == 0 && isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else if category.sizeBytes == 0 {
                        // Folders exist but hold nothing — nicer than the
                        // formatter's "Zero KB".
                        Text("Empty")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(formatBytes(category.sizeBytes))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if !isEmpty {
                        Text("\(category.items.count) item\(category.items.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator.opacity(0.5)),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
