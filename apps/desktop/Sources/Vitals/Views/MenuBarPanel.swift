import SwiftUI
import Charts

/// The menu bar dropdown: live readings and sparklines, in the main window's
/// design language.
struct MenuBarPanel: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sparklines
            memoryRow
            Divider()
                .opacity(0.5)
            fanSection
            Divider()
                .opacity(0.5)
            actions
        }
        .padding(14)
        .frame(width: 330)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(HardwareInfo.chipName)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.thermalState.tint)
                        .frame(width: 6, height: 6)
                    Text(model.thermalState.label)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(model.thermalState.tint.opacity(0.14)))
                .foregroundStyle(model.thermalState.tint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(model.averageCPUTemp.map { settings.formatWithUnit($0, decimals: 0) } ?? "—")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .numericTransition()
                    .foregroundStyle(model.averageCPUTemp.map(tempGradientColor) ?? .primary)
                Text("avg CPU")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sparklines

    /// The dropdown's charts are 36 px tall — 100 points is already more
    /// than one per pixel, and a third of the marks makes the panel open
    /// noticeably snappier.
    private var sparkData: [VitalsModel.Sample] {
        model.chartHistory.thinned(to: 100)
    }

    /// Two fixed columns (never `.adaptive`, per the perf rules). Four metrics
    /// land as a clean 2×2; three fill the first row plus one. A single row of
    /// four was far too narrow — labels and values truncated to "Te…"/"M…/12…".
    private let sparkColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var sparklines: some View {
        let data = sparkData
        return LazyVGrid(columns: sparkColumns, spacing: 8) {
            sparkline(
                title: "Temp",
                value: model.hottestCPUSensor.map { settings.format($0.celsius, decimals: 0) } ?? "—",
                color: .orange
            ) {
                ForEach(data) { sample in
                    LineMark(x: .value("t", sample.time), y: .value("v", sample.hottestCPU))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                }
            }
            sparkline(
                title: "CPU",
                value: String(format: "%.0f%%", model.cpuUsage),
                color: .blue
            ) {
                ForEach(data) { sample in
                    AreaMark(x: .value("t", sample.time), y: .value("v", sample.usage))
                        .foregroundStyle(.blue.opacity(0.18))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("t", sample.time), y: .value("v", sample.usage))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                }
            }
            sparkline(
                title: "Memory",
                value: String(format: "%.1fG", gigabytes(model.memory?.used ?? 0)),
                color: .indigo
            ) {
                ForEach(data) { sample in
                    AreaMark(x: .value("t", sample.time), y: .value("v", gigabytes(sample.memoryUsed)))
                        .foregroundStyle(.indigo.opacity(0.18))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("t", sample.time), y: .value("v", gigabytes(sample.memoryUsed)))
                        .foregroundStyle(.indigo)
                        .interpolationMethod(.catmullRom)
                }
            }
            if let network = model.network {
                sparkline(
                    title: "Network",
                    value: "↓ " + NetworkFormat.rate(network.totalInPerSec),
                    color: .mint
                ) {
                    ForEach(data) { sample in
                        if let down = sample.netInPerSec {
                            AreaMark(x: .value("t", sample.time), y: .value("v", down))
                                .foregroundStyle(.mint.opacity(0.18))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("t", sample.time), y: .value("v", down))
                                .foregroundStyle(.mint)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                }
            }
            if let diskIO = model.diskIO {
                sparkline(
                    title: "Disk",
                    value: "R " + NetworkFormat.rate(diskIO.readPerSec),
                    color: .yellow
                ) {
                    ForEach(data) { sample in
                        if let read = sample.diskReadPerSec {
                            AreaMark(x: .value("t", sample.time), y: .value("v", read))
                                .foregroundStyle(.yellow.opacity(0.18))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("t", sample.time), y: .value("v", read))
                                .foregroundStyle(.yellow)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                }
            }
            if let utilization = model.gpu?.utilization {
                sparkline(
                    title: "GPU",
                    value: String(format: "%.0f%%", utilization),
                    color: .purple
                ) {
                    ForEach(data) { sample in
                        if let usage = sample.gpuUsage {
                            AreaMark(x: .value("t", sample.time), y: .value("v", usage))
                                .foregroundStyle(.purple.opacity(0.18))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("t", sample.time), y: .value("v", usage))
                                .foregroundStyle(.purple)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                }
            }
        }
    }

    private func sparkline<Content: ChartContent>(
        title: String,
        value: String,
        color: Color,
        @ChartContentBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .numericTransition()
                    .foregroundStyle(color)
            }
            Chart(content: content)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var memoryRow: some View {
        if let memory = model.memory {
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f / %.0f GB", gigabytes(memory.used), gigabytes(memory.total)))
                    .monospacedDigit()
                if memory.swapUsed > 0 {
                    Text("· swap \(String(format: "%.1f GB", gigabytes(memory.swapUsed)))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(pressureColor(memory.pressure))
                    .frame(width: 7, height: 7)
                Text(memory.pressure.label)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    // MARK: Fans

    @ViewBuilder
    private var fanSection: some View {
        if let fan = model.fans.first {
            HStack {
                Image(systemName: "fan")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.cyan)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.cyan.opacity(0.14))
                    )
                Text("\(Int(fan.rpm)) rpm")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .numericTransition()
                Spacer()
                if let manual = fan.isManual {
                    Text(manual ? "Manual" : "Automatic")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(manual ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Vitals", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .medium))
            }
            .controlSize(.small)
            Spacer()
            Button {
                navigator.section = .settings
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .help("Quit Vitals")
        }
    }
}
