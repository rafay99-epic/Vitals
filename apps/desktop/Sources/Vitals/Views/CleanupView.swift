import SwiftUI

/// The Cleanup tab: categories of regenerable data with sizes, cleaned on
/// explicit confirmation. Caches and logs are deleted (trashing them would
/// free nothing); the Trash category empties permanently and says so.
struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryList
            Divider()
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

    private var header: some View {
        HStack {
            Text(model.totalBytes > 0 ? "\(formatBytes(model.totalBytes)) reclaimable" : "Reclaimable space")
                .font(.headline)
            if model.isScanning {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan")
            .disabled(model.isScanning)
        }
        .padding(12)
    }

    private var categoryList: some View {
        List {
            ForEach(model.categories) { category in
                CategoryRow(
                    category: category,
                    isSelected: Binding(
                        get: { model.selected.contains(category.kind) },
                        set: { selected in
                            if selected {
                                model.selected.insert(category.kind)
                            } else {
                                model.selected.remove(category.kind)
                            }
                        }
                    )
                )
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            Text("Only regenerable data is offered — documents and settings are never touched.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(role: .destructive) {
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
            .disabled(model.selected.isEmpty || model.isCleaning || model.selectedBytes == 0)
        }
        .padding(12)
    }
}

private struct CategoryRow: View {
    let category: CleanupCategory
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(category.items.isEmpty)
            Image(systemName: category.kind.symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.kind.title)
                Text(category.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(category.items.isEmpty ? "Nothing found" : formatBytes(category.sizeBytes))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
