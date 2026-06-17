import SwiftUI

/// A card whose body collapses behind a tappable header — used to keep heavy or
/// secondary detail (per-core grid, top processes, battery) out of the way until
/// asked for. Collapsed content isn't built, so it costs nothing until opened.
struct CollapsibleCard<Content: View>: View {
    let title: String
    let symbol: String
    var subtitle: String?
    @State private var expanded: Bool
    @ViewBuilder var content: () -> Content

    init(title: String, symbol: String, subtitle: String? = nil,
         expanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        _expanded = State(initialValue: expanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }
}

/// CPU subsystem: a compact average/hottest/load summary, with the full per-core
/// die map tucked behind a disclosure (it's 20+ cells on modern chips — most
/// glances only need the summary).
struct CPUCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showCores = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("CPU", systemImage: "cpu")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 24) {
                summaryStat("Average", model.averageCPUTemp.map { settings.format($0) } ?? "—")
                summaryStat("Hottest", model.hottestCPUSensor.map { settings.format($0.celsius) } ?? "—",
                            note: model.hottestCPUSensor?.label)
                summaryStat("Load", String(format: "%.0f%%", model.cpuUsage),
                            note: "\(HardwareInfo.coreCount) cores")
                Spacer(minLength: 0)
            }

            // Apple Silicon: split the blended load into Performance vs
            // Efficiency cores. Hidden when there's no trusted split.
            if let clusters = model.cpuClusters {
                VStack(alignment: .leading, spacing: 7) {
                    ClusterMeter(label: "Performance", percent: clusters.performance, tint: .accentColor)
                    ClusterMeter(label: "Efficiency", percent: clusters.efficiency, tint: .teal)
                }
            }

            if !model.cpuSensors.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showCores.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(showCores ? 90 : 0))
                        Text("Per-core temperatures (\(model.cpuSensors.count))")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showCores { CoreTempGrid(sensors: model.cpuSensors) }
            }
        }
        // Match the paired card's height in the row (see SectionCard).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .cardBackground()
    }

    private func summaryStat(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericTransition()
            if let note {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
