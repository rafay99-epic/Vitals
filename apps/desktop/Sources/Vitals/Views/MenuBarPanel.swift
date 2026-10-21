import SwiftUI

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
                .capsuleTag(model.thermalState.tint, fill: 0.14)
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

    /// The dropdown's sparklines are 36 px tall, so 100 points is already more
    /// than one per pixel.
    private var sparkData: [VitalsModel.Sample] {
        model.chartHistory.thinned(to: 100)
    }

    /// Two fixed columns (never `.adaptive`). A single row of four truncated the
    /// labels and values.
    private let sparkColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var sparklines: some View {
        let data = sparkData
        return LazyVGrid(columns: sparkColumns, spacing: 8) {
            sparkline(
                title: "Temp",
                value: model.hottestCPUSensor.map { settings.format($0.celsius, decimals: 0) } ?? "—",
                color: .orange,
                values: data.map(\.hottestCPU)
            )
            sparkline(
                title: "CPU",
                value: String(format: "%.0f%%", model.cpuUsage),
                color: .blue,
                values: data.map(\.usage)
            )
            sparkline(
                title: "Memory",
                value: String(format: "%.1fG", gigabytes(model.memory?.used ?? 0)),
                color: .indigo,
                values: data.map { gigabytes($0.memoryUsed) }
            )
            if let network = model.network {
                sparkline(
                    title: "Network",
                    value: "↓ " + NetworkFormat.rate(network.totalInPerSec),
                    color: .mint,
                    values: data.compactMap(\.netInPerSec)
                )
            }
            if let diskIO = model.diskIO {
                sparkline(
                    title: "Disk",
                    value: "R " + NetworkFormat.rate(diskIO.readPerSec),
                    color: .yellow,
                    values: data.compactMap(\.diskReadPerSec)
                )
            }
            if let utilization = model.gpu?.utilization {
                sparkline(
                    title: "GPU",
                    value: String(format: "%.0f%%", utilization),
                    color: .purple,
                    values: data.compactMap(\.gpuUsage)
                )
            }
        }
    }

    private func sparkline(title: String, value: String, color: Color, values: [Double]) -> some View {
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
            Sparkline(values: values, tint: color)
                .frame(height: 36)
        }
        .padding(8)
        .insetCard(fill: 0.4, border: 0.4, cornerRadius: 9)
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
                IconTile(symbol: "fan", tint: .cyan, size: 24, cornerRadius: 6)
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
