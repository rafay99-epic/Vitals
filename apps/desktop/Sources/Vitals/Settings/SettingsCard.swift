import SwiftUI

// MARK: - Card building blocks

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                IconTile(symbol: symbol, tint: tint)
                HighlightLabel(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .insetCard(fill: 0.35)
    }
}

struct SwitchRow: View {
    let label: String
    var caption: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HighlightLabel(label)
                    .font(.system(size: 12.5))
                if let caption {
                    HighlightLabel(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A switch that adds/removes one reading from the menu-bar set.
struct MenuBarMetricToggle: View {
    let metric: MenuBarMetric
    @Binding var selection: Set<MenuBarMetric>

    var body: some View {
        Toggle(isOn: Binding(
            get: { selection.contains(metric) },
            set: { on in
                if on { selection.insert(metric) } else { selection.remove(metric) }
            }
        )) {
            HStack(spacing: 8) {
                IconTile(symbol: metric.symbol, tint: .blue, size: 22, font: .system(size: 11, weight: .medium), cornerRadius: 6)
                HighlightLabel(metric.label)
                    .font(.system(size: 12.5))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

func settingsRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
    HStack {
        HighlightLabel(label)
            .font(.system(size: 12.5))
        Spacer()
        control()
    }
}
