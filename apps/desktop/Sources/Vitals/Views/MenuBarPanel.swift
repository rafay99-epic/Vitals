import SwiftUI
import Charts

/// The window-style menu bar dropdown: live readings, a temperature
/// sparkline, and quick fan control.
struct MenuBarPanel: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var fanControl: FanController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sparklines
            memoryRow
            Divider()
            fanSection
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 330)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HardwareInfo.chipName)
                    .font(.headline)
                Text(model.thermalState.label + " thermal pressure")
                    .font(.caption)
                    .foregroundStyle(model.thermalState.tint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.averageCPUTemp.map { settings.formatWithUnit($0, decimals: 0) } ?? "—")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
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

    private var sparklines: some View {
        let data = sparkData
        return HStack(spacing: 8) {
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
        }
    }

    @ViewBuilder
    private var memoryRow: some View {
        if let memory = model.memory {
            HStack(spacing: 6) {
                Image(systemName: "memorychip").foregroundStyle(.secondary)
                Text(String(format: "%.1f / %.0f GB", gigabytes(memory.used), gigabytes(memory.total)))
                if memory.swapUsed > 0 {
                    Text("· swap \(String(format: "%.1f GB", gigabytes(memory.swapUsed)))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(pressureColor(memory.pressure)).frame(width: 8, height: 8)
                Text(memory.pressure.label).foregroundStyle(.secondary)
            }
            .font(.caption)
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
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption).monospacedDigit().foregroundStyle(color)
            }
            Chart(content: content)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
    }

    // MARK: Fans

    @ViewBuilder
    private var fanSection: some View {
        if let fan = model.fans.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("\(Int(fan.rpm)) rpm", systemImage: "fan")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text(fanModeLabel(fan))
                        .font(.caption2)
                        .foregroundStyle(isManual(fan) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }

                if fanControl.isInstalled, fan.maxRPM > fan.minRPM {
                    HStack(spacing: 6) {
                        presetButton("Auto", isOn: !isManual(fan)) {
                            fanControl.setAuto(fan: fan.id)
                        }
                        presetButton("Quiet", isOn: false) {
                            fanControl.setTarget(fan: fan.id, rpm: Int(fan.minRPM))
                        }
                        presetButton("Med", isOn: false) {
                            fanControl.setTarget(fan: fan.id, rpm: Int((fan.minRPM + fan.maxRPM) / 2))
                        }
                        presetButton("Max", isOn: false) {
                            fanControl.setTarget(fan: fan.id, rpm: Int(fan.maxRPM))
                        }
                    }
                } else if !fanControl.isInstalled {
                    Text("Enable fan control in the Vitals window to set speed here.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func presetButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isOn ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.5)))
        )
        .disabled(fanControl.isWorking)
    }

    // MARK: Actions

    private var actions: some View {
        HStack {
            Button("Open Vitals") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button("Settings") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .controlSize(.small)
    }

    // MARK: Helpers

    private func isManual(_ fan: SMC.Fan) -> Bool {
        fanControl.target(for: fan.id)?.mode == .manual
    }

    private func fanModeLabel(_ fan: SMC.Fan) -> String {
        isManual(fan) ? "Manual" : "Automatic"
    }
}
