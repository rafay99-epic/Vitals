import SwiftUI
import Charts

/// The window-style menu bar dropdown: live readings, sparklines, and quick
/// fan control — in the same design language as the main window.
struct MenuBarPanel: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var fanControl: FanController
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.openWindow) private var openWindow
    @Namespace private var presetIndicator
    @State private var copied = false

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
        VitalsModel.downsample(model.chartHistory, to: 100)
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

    private enum FanPreset: String, CaseIterable, Identifiable {
        case auto = "Auto", quiet = "Quiet", med = "Med", max = "Max"
        var id: String { rawValue }
    }

    @ViewBuilder
    private var fanSection: some View {
        if let fan = model.fans.first {
            VStack(alignment: .leading, spacing: 9) {
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
                    Text(isManual(fan) ? "Manual" : "Automatic")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isManual(fan) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }

                if fanControl.isInstalled, fan.maxRPM > fan.minRPM {
                    presetBar(fan)
                } else if !fanControl.isInstalled {
                    Text("Enable fan control in the Vitals window to set speed here.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func presetBar(_ fan: SMC.Fan) -> some View {
        HStack(spacing: 2) {
            ForEach(FanPreset.allCases) { preset in
                presetButton(preset, fan: fan)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    private func presetButton(_ preset: FanPreset, fan: SMC.Fan) -> some View {
        let selected = isSelected(preset, fan: fan)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                apply(preset, fan: fan)
            }
        } label: {
            Text(preset.rawValue)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if selected {
                Capsule()
                    .fill(.quaternary)
                    .matchedGeometryEffect(id: "fan-preset", in: presetIndicator)
            }
        }
        .disabled(fanControl.isWorking)
    }

    private func isSelected(_ preset: FanPreset, fan: SMC.Fan) -> Bool {
        guard let command = fanControl.target(for: fan.id), command.mode == .manual else {
            return preset == .auto
        }
        let target = Int(command.rpm)
        switch preset {
        case .auto: return false
        case .quiet: return target == Int(fan.minRPM)
        case .med: return target == Int((fan.minRPM + fan.maxRPM) / 2)
        case .max: return target == Int(fan.maxRPM)
        }
    }

    private func apply(_ preset: FanPreset, fan: SMC.Fan) {
        switch preset {
        case .auto: fanControl.setAuto(fan: fan.id)
        case .quiet: fanControl.setTarget(fan: fan.id, rpm: Int(fan.minRPM))
        case .med: fanControl.setTarget(fan: fan.id, rpm: Int((fan.minRPM + fan.maxRPM) / 2))
        case .max: fanControl.setTarget(fan: fan.id, rpm: Int(fan.maxRPM))
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
                DiagnosticSnapshot.copyToPasteboard(model: model, settings: settings)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 12))
                    .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.primary))
            }
            .controlSize(.small)
            .help("Copy diagnostics to clipboard")
            Button {
                openWindow(id: "help")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .help("Vitals Help")
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

    // MARK: Helpers

    private func isManual(_ fan: SMC.Fan) -> Bool {
        fanControl.target(for: fan.id)?.mode == .manual
    }
}
