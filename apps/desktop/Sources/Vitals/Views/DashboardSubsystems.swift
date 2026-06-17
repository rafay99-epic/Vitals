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
                    clusterMeter("Performance", clusters.performance, tint: .accentColor)
                    clusterMeter("Efficiency", clusters.efficiency, tint: .teal)
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

                if showCores { dieGrid }
            }
        }
        // Match the paired card's height in the row (see SectionCard).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .cardBackground()
    }

    private func clusterMeter(_ label: String, _ percent: Double, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            utilizationBar(fraction: percent / 100, tint: tint)
            Text(String(format: "%.0f%%", percent))
                .font(.caption).monospacedDigit().numericTransition()
                .frame(width: 38, alignment: .trailing)
        }
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

    private var dieGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(model.cpuSensors) { sensor in
                    DieCell(sensor: sensor)
                }
            }
            dieLegend
        }
    }

    @ViewBuilder
    private var dieLegend: some View {
        let temps = model.cpuSensors.map(\.celsius)
        if let coolest = temps.min(), let hottest = temps.max() {
            HStack(spacing: 12) {
                Text("Coolest \(settings.format(coolest, decimals: 0))")
                Text("Hottest \(settings.format(hottest, decimals: 0))")
                Spacer()
                Capsule()
                    .fill(LinearGradient(
                        colors: [tempGradientColor(40), tempGradientColor(60), tempGradientColor(75), tempGradientColor(90)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 96, height: 5)
                Text("\(settings.format(40, decimals: 0))–\(settings.format(90, decimals: 0))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}
