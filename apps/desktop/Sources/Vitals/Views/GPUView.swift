import SwiftUI
import Charts

/// The GPU tab: a deeper look than the Dashboard's summary card — utilization
/// broken into renderer/tiler, the unified-memory working set, and live power
/// for the GPU and Neural Engine rails. Apple Silicon exposes no GPU-specific
/// temperature (CPU and GPU share one die and the diodes aren't labelled per
/// block), so none is shown — labelling a generic die reading "GPU" would break
/// the honesty rule.
struct GPUView: View {
    @EnvironmentObject private var model: VitalsModel
    /// True only while the GPU tab is the visible one. The tab stays mounted for
    /// instant switching, so without this the history chart would rebuild its
    /// marks on every sample tick in the background — gating it keeps idle cost
    /// to zero when another tab is up.
    let isActive: Bool

    var body: some View {
        MetricScroll {
            if let gpu = model.gpu {
                GPUHeroCard(gpu: gpu)
                GPUUtilizationCard(gpu: gpu, isActive: isActive)
                GPUMemoryCard(gpu: gpu)
                GPUPowerCard()
            } else {
                EmptyStateView(
                    symbol: "cpu.fill",
                    tint: .purple,
                    title: "No GPU detected",
                    message: "Vitals couldn't read a GPU on this Mac. That's expected in a virtual machine or with restricted hardware access — details appear here once a GPU is available."
                ) { EmptyView() }
            }
        }
    }
}

// MARK: - Hero

private struct GPUHeroCard: View {
    let gpu: GPUSnapshot

    var body: some View {
        SectionCard(title: "GPU", symbol: "cpu.fill") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(gpu.utilization.map { String(format: "%.0f%%", $0) } ?? "—")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition()
                    Text("utilization")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let name = gpu.name {
                            Text(name).font(.headline)
                        }
                        if let cores = gpu.coreCount {
                            Text("\(cores)-core GPU").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                utilizationBar(fraction: (gpu.utilization ?? 0) / 100, tint: .purple)
            }
        }
    }
}

// MARK: - Utilization breakdown + history

private struct GPUUtilizationCard: View {
    @EnvironmentObject private var model: VitalsModel
    let gpu: GPUSnapshot
    let isActive: Bool

    var body: some View {
        SectionCard(title: "Utilization", symbol: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 14) {
                meterRow("Device", gpu.utilization, tint: .purple)
                if gpu.rendererUtilization != nil || gpu.tilerUtilization != nil {
                    Divider()
                    meterRow("Renderer", gpu.rendererUtilization, tint: .indigo)
                    meterRow("Tiler", gpu.tilerUtilization, tint: .teal)
                }
                // Only build the chart while this tab is showing — see GPUView.
                if isActive, model.chartHistory.contains(where: { $0.gpuUsage != nil }) {
                    Divider()
                    Deferred { history }.frame(height: 150)
                }
            }
        }
    }

    private func meterRow(_ label: String, _ value: Double?, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            utilizationBar(fraction: (value ?? 0) / 100, tint: tint)
            Text(value.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.callout)
                .monospacedDigit()
                .numericTransition()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var history: some View {
        Chart(model.chartHistory) { sample in
            if let usage = sample.gpuUsage {
                AreaMark(x: .value("Time", sample.time), y: .value("%", usage))
                    .foregroundStyle(LinearGradient(colors: [.purple.opacity(0.35), .purple.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.time), y: .value("%", usage))
                    .foregroundStyle(.purple)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("%")
    }
}

// MARK: - Unified memory

private struct GPUMemoryCard: View {
    let gpu: GPUSnapshot

    var body: some View {
        SectionCard(title: "Memory", symbol: "memorychip") {
            if gpu.memoryUsed != nil {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    bar
                    legend
                    Text("Unified memory shared with the system — the GPU draws from the same pool as the CPU.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("GPU memory statistics unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(format: "%.2f GB", gigabytes(gpu.memoryUsed ?? 0)))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .numericTransition()
            Text("in use").font(.callout).foregroundStyle(.secondary)
            Spacer()
            if let total = gpu.memoryTotal, total > 0 {
                Text(String(format: "of %.0f GB working set", gigabytes(total)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// In-use (solid) within the driver's allocation (faint) within the working
    /// set (track) — three honest depths of the same unified pool.
    private var bar: some View {
        GeometryReader { geometry in
            let total = max(Double(gpu.memoryTotal ?? gpu.memoryAllocated ?? gpu.memoryUsed ?? 1), 1)
            let used = Double(gpu.memoryUsed ?? 0)
            let allocated = max(Double(gpu.memoryAllocated ?? gpu.memoryUsed ?? 0), used)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.purple.opacity(0.25))
                    .frame(width: geometry.size.width * min(allocated / total, 1))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.purple)
                    .frame(width: geometry.size.width * min(used / total, 1))
            }
        }
        .frame(height: 14)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            swatch(.purple, "In use", gpu.memoryUsed)
            if let allocated = gpu.memoryAllocated {
                swatch(.purple.opacity(0.25), "Allocated", allocated)
            }
            Spacer()
        }
        .font(.caption)
    }

    private func swatch(_ color: Color, _ label: String, _ bytes: UInt64?) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label).foregroundStyle(.secondary)
            Text(bytes.map { String(format: "%.2f GB", gigabytes($0)) } ?? "—").monospacedDigit()
        }
    }
}

// MARK: - Neural Engine + power rails

private struct GPUPowerCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Power", symbol: "bolt.fill") {
            if let power = model.power {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        PowerTile(title: "GPU", watts: power.gpuWatts, symbol: "cpu.fill", tint: .purple)
                        PowerTile(title: "Neural Engine", watts: power.aneWatts, symbol: "brain", tint: .pink)
                        PowerTile(title: "CPU", watts: power.cpuWatts, symbol: "cpu", tint: .blue)
                    }
                    Text("Live draw of each SoC rail. The Neural Engine sits near zero until Core ML or vision work runs — Vitals reports what it reads, never an assumed maximum.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Power readings unavailable on this Mac.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }
}

/// A small fraction-filled bar in the card language, used for the GPU meters.
private func utilizationBar(fraction: Double, tint: Color) -> some View {
    GeometryReader { geometry in
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.secondary.opacity(0.15))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint)
                .frame(width: geometry.size.width * min(max(fraction, 0), 1))
        }
    }
    .frame(height: 12)
}
