import SwiftUI
import Charts

/// Top CPU consumers. Wrapper-free content so it can sit inside a CollapsibleCard.
struct TopProcessesContent: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        if model.topProcesses.isEmpty {
            Text("Gathering…")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.topProcesses) { process in
                    HStack {
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                Text("CPU per process · 100% = one core")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct FanCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var fanControl: FanController
    @State private var pendingRPM: [Int: Double] = [:]

    var body: some View {
        SectionCard(title: "Fans", symbol: "fan") {
            if model.fans.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: model.hasSMC ? "fan.slash" : "questionmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(model.hasSMC ? "This Mac is fanless — it cools passively." : "Fan data unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.fans) { fan in
                        fanRow(fan)
                        if fanControl.isInstalled {
                            fanControls(fan)
                        }
                        if fan.id != model.fans.last?.id {
                            Divider()
                        }
                    }
                    controlFooter
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            }
        }
    }

    private func fanRow(_ fan: SMC.Fan) -> some View {
        HStack(spacing: 16) {
            Gauge(value: gaugeValue(fan), in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "fan")
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(fan.rpm)) rpm")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .numericTransition()
                Text(modeLine(fan))
                    .font(.caption)
                    .foregroundStyle(isManual(fan) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Text("Range \(Int(fan.minRPM))–\(Int(fan.maxRPM)) rpm")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func fanControls(_ fan: SMC.Fan) -> some View {
        if fan.maxRPM > fan.minRPM {
            HStack(spacing: 8) {
                Slider(value: sliderBinding(fan), in: fan.minRPM...fan.maxRPM) { editing in
                    if !editing {
                        fanControl.setTarget(fan: fan.id, rpm: Int(sliderValue(fan)))
                    }
                }
                .controlSize(.small)
                .disabled(fanControl.isWorking)

                Text("\(Int(sliderValue(fan)))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)

                Button("Auto") {
                    pendingRPM[fan.id] = nil
                    fanControl.setAuto(fan: fan.id)
                }
                .controlSize(.small)
                .disabled(fanControl.isWorking || !isManual(fan))
            }
        }
    }

    @ViewBuilder
    private var controlFooter: some View {
        if let error = fanControl.lastError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if fanControl.isInstalled {
            HStack {
                Text("Manual speed overrides macOS cooling, within the rated range.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Disable…") {
                    Task { await fanControl.remove(fanCount: model.fans.count) }
                }
                .controlSize(.mini)
                .disabled(fanControl.isWorking)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await fanControl.install() }
                } label: {
                    Label(fanControl.isWorking ? "Installing…" : "Enable Fan Control", systemImage: "fan")
                }
                .disabled(fanControl.isWorking)
                Text("Installs a small helper (one password) so you can set fan speed without a prompt each time. macOS thermal safety stays active.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func isManual(_ fan: SMC.Fan) -> Bool {
        fanControl.target(for: fan.id)?.mode == .manual
    }

    private func modeLine(_ fan: SMC.Fan) -> String {
        if isManual(fan) {
            let target = fanControl.target(for: fan.id).map { Int($0.rpm) } ?? Int(fan.targetRPM)
            return "Manual · target \(target) rpm"
        }
        return "Automatic"
    }

    private func sliderValue(_ fan: SMC.Fan) -> Double {
        if let pending = pendingRPM[fan.id] { return pending }
        if let command = fanControl.target(for: fan.id), command.mode == .manual { return command.rpm }
        return min(max(fan.targetRPM, fan.minRPM), fan.maxRPM)
    }

    private func sliderBinding(_ fan: SMC.Fan) -> Binding<Double> {
        Binding(
            get: { sliderValue(fan) },
            set: { pendingRPM[fan.id] = $0 }
        )
    }

    private func gaugeValue(_ fan: SMC.Fan) -> Double {
        guard fan.maxRPM > 0 else { return 0 }
        return min(max(fan.rpm / fan.maxRPM, 0), 1)
    }
}

struct MemoryCard: View {
    @EnvironmentObject private var model: VitalsModel

    private struct Segment: Identifiable {
        let label: String
        let bytes: UInt64
        let color: Color
        var id: String { label }
    }

    var body: some View {
        SectionCard(title: "Memory", symbol: "memorychip") {
            if let memory = model.memory {
                VStack(alignment: .leading, spacing: 12) {
                    header(memory)
                    breakdownBar(memory)
                    legend(memory)
                    Divider()
                    swapAndPressure(memory)
                }
            } else {
                Text("Memory statistics unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func header(_ memory: MemorySnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(format: "%.2f GB", gigabytes(memory.used)))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .numericTransition()
            Text("used of \(String(format: "%.0f GB", gigabytes(memory.total)))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            pressureBadge(memory.pressure)
        }
    }

    private func segments(_ memory: MemorySnapshot) -> [Segment] {
        [
            Segment(label: "App", bytes: memory.app, color: .blue),
            Segment(label: "Wired", bytes: memory.wired, color: .orange),
            Segment(label: "Compressed", bytes: memory.compressed, color: .purple),
            Segment(label: "Cached", bytes: memory.cached, color: .green.opacity(0.7)),
        ]
    }

    private func breakdownBar(_ memory: MemorySnapshot) -> some View {
        GeometryReader { geometry in
            let total = max(Double(memory.total), 1)
            HStack(spacing: 1) {
                ForEach(segments(memory)) { segment in
                    segment.color
                        .frame(width: geometry.size.width * Double(segment.bytes) / total)
                }
                Color.secondary.opacity(0.15)  // free
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 14)
    }

    private func legend(_ memory: MemorySnapshot) -> some View {
        let items = segments(memory) + [Segment(label: "Free", bytes: memory.free, color: .secondary.opacity(0.3))]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], spacing: 4) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 9, height: 9)
                    Text(item.label).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f GB", gigabytes(item.bytes))).monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    private func swapAndPressure(_ memory: MemorySnapshot) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Swap used").font(.caption).foregroundStyle(.secondary)
                Text(swapText(memory))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(memory.swapUsed > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory pressure").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle().fill(pressureColor(memory.pressure)).frame(width: 9, height: 9)
                    Text(memory.pressure.label)
                        .font(.system(.body, design: .rounded, weight: .medium))
                }
            }
            Spacer()
        }
    }

    private func swapText(_ memory: MemorySnapshot) -> String {
        guard memory.swapTotal > 0 else { return "None" }
        return String(format: "%.2f GB of %.1f GB", gigabytes(memory.swapUsed), gigabytes(memory.swapTotal))
    }

    private func pressureBadge(_ pressure: MemoryPressure) -> some View {
        Text(pressure.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(pressureColor(pressure).opacity(0.18)))
            .foregroundStyle(pressureColor(pressure))
    }
}

/// Battery detail rows. Wrapper-free so it can sit inside a CollapsibleCard.
struct BatteryContent: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    /// Charge-state SF Symbol for the section header (used by the dashboard).
    static func symbol(for battery: BatterySnapshot?) -> String {
        guard let battery else { return "battery.100percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        Group {
            if let battery = model.battery {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(battery.percent))%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .numericTransition()
                        Text(stateLine(for: battery))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Gauge(value: battery.percent / 100) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(chargeTint(battery))
                            .frame(width: 200)
                    }

                    Divider()
                        .frame(height: 64)

                    VStack(alignment: .leading, spacing: 6) {
                        if let health = battery.healthPercent {
                            detailRow(symbol: "heart", text: healthLine(health: health, cycles: battery.cycleCount))
                        }
                        if let watts = battery.watts, abs(watts) > 0.1 {
                            detailRow(
                                symbol: "bolt",
                                text: watts > 0
                                    ? String(format: "Charging at %.1f W", watts)
                                    : String(format: "Drawing %.1f W from battery", -watts)
                            )
                        }
                        if let temp = model.batteryTemp {
                            detailRow(symbol: "thermometer.low", text: "Battery temperature \(settings.formatWithUnit(temp))")
                        }
                        if let minutes = battery.timeRemainingMinutes {
                            detailRow(
                                symbol: "clock",
                                text: battery.externalPower
                                    ? "About \(timeText(minutes)) until full"
                                    : "About \(timeText(minutes)) remaining"
                            )
                        }
                    }
                    Spacer()
                }
            } else {
                Text("No battery found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func stateLine(for battery: BatterySnapshot) -> String {
        if battery.isCharging { return "Charging" }
        if battery.externalPower { return battery.fullyCharged ? "Fully charged, on power adapter" : "On power adapter" }
        return "On battery"
    }

    private func healthLine(health: Double, cycles: Int?) -> String {
        var line = String(format: "Health %.0f%%", health)
        if let cycles { line += " · \(cycles) cycles" }
        return line
    }

    private func detailRow(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
        }
        .font(.callout)
    }

    private func chargeTint(_ battery: BatterySnapshot) -> Color {
        if battery.isCharging { return .green }
        switch battery.percent {
        case ..<20: return .red
        case ..<50: return .orange
        default: return .green
        }
    }

    private func timeText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
