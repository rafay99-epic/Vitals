import SwiftUI

// MARK: - Category card

private extension CleanupCategory.Kind {
    var tint: Color {
        switch self {
        case .xcode: return .blue
        case .devCaches: return .orange
        case .deviceSupport: return .cyan
        case .browserCaches: return .green
        case .deviceFirmware: return .indigo
        case .deviceBackups: return .red
        case .homebrew: return .yellow
        case .appCaches: return .purple
        case .logs: return .teal
        case .trash: return .red
        case .recentItems: return .indigo
        case .aiCaches: return .purple
        case .systemCaches: return .gray
        case .systemLogs: return .mint
        case .crashReports: return .red
        case .systemTemp: return .brown
        case .gpuCaches: return .pink
        }
    }
}

struct CategoryCard: View {
    let category: CleanupCategory
    let isScanning: Bool
    let isSelected: Bool
    let toggle: () -> Void

    /// Disabled only once a scan has settled with nothing to remove.
    private var hasNothing: Bool { !isScanning && category.sizeBytes == 0 }

    private var emptyLabel: String {
        if category.kind.requiresAdmin { return "Nothing old enough" }
        return category.items.isEmpty ? "Nothing found" : "Empty"
    }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    IconTile(symbol: category.kind.symbol, tint: category.kind.tint, size: 28, font: .system(size: 13, weight: .medium))
                    Text(category.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    if category.kind.requiresAdmin {
                        Image(systemName: "lock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Removing these needs administrator rights")
                    }
                    if category.kind.isDestructive {
                        Text("PERMANENT")
                            .font(.system(size: 9, weight: .bold))
                            .capsuleTag(.red, fill: 0.16, horizontal: 5, vertical: 1)
                            .help("Not regenerable — deleted permanently and can't be recovered")
                    }
                    Spacer()
                    SelectionMark(selected: isSelected)
                }

                Text(category.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)

                HStack(alignment: .firstTextBaseline) {
                    if isScanning && category.sizeBytes == 0 {
                        ProgressView()
                            .controlSize(.small)
                    } else if category.sizeBytes == 0 {
                        Text(emptyLabel)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(formatBytes(category.sizeBytes))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if category.sizeBytes > 0 {
                        Text("\(category.items.count) item\(category.items.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .insetCard(fill: 0.35, selected: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(hasNothing && !isSelected)
        .opacity(hasNothing ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
