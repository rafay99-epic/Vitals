import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statCards
                TemperatureHistoryCard()
                HStack(alignment: .top, spacing: 16) {
                    PerCoreCard()
                    FanCard()
                        .frame(width: 280)
                }
                HStack(alignment: .top, spacing: 16) {
                    CPUUsageCard()
                    TopProcessesCard()
                        .frame(width: 280)
                }
                BatteryCard()
                footer
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 800, minHeight: 680)
        .navigationTitle("Vitals")
        .toolbar {
            ToolbarItem {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("Vitals settings")
            }
        }
    }

    private var statCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            StatCard(
                title: "Average CPU",
                value: model.averageCPUTemp.map { settings.format($0) } ?? "—",
                subtitle: "\(model.cpuSensors.count) die sensors",
                symbol: "cpu",
                tint: model.averageCPUTemp.map(tempColor) ?? .secondary
            )
            StatCard(
                title: "Hottest Core",
                value: model.hottestCPUSensor.map { settings.format($0.celsius) } ?? "—",
                subtitle: model.hottestCPUSensor.map { "Sensor \($0.label)" } ?? "",
                symbol: "flame",
                tint: model.hottestCPUSensor.map { tempColor($0.celsius) } ?? .secondary
            )
            StatCard(
                title: "Fan",
                value: fanValue,
                subtitle: fanSubtitle,
                symbol: "fan",
                tint: .cyan
            )
            StatCard(
                title: "CPU Usage",
                value: String(format: "%.0f%%", model.cpuUsage),
                subtitle: "\(HardwareInfo.coreCount) cores",
                symbol: "gauge.with.dots.needle.50percent",
                tint: .blue
            )
            StatCard(
                title: "Memory",
                value: String(format: "%.1f GB", gigabytes(model.memoryUsed)),
                subtitle: String(format: "of %.0f GB used", gigabytes(model.memoryTotal)),
                symbol: "memorychip",
                tint: .indigo
            )
            StatCard(
                title: "Thermal Pressure",
                value: model.thermalState.label,
                subtitle: "Reported by macOS",
                symbol: "thermometer.medium",
                tint: model.thermalState.tint
            )
        }
    }

    private var fanValue: String {
        guard model.hasSMC else { return "—" }
        guard let fan = model.fans.first else { return "Fanless" }
        return "\(Int(fan.rpm)) rpm"
    }

    private var fanSubtitle: String {
        guard let fan = model.fans.first else { return "No fan detected" }
        return model.fans.count > 1 ? "\(model.fans.count) fans" : "Max \(Int(fan.maxRPM)) rpm"
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(HardwareInfo.chipName)
            Text("·")
            Text(HardwareInfo.osVersion)
            Text("·")
            Text("Up \(HardwareInfo.uptimeText)")
            if let ssd = model.ssdTemp {
                Text("·")
                Text("SSD \(settings.format(ssd, decimals: 0))")
            }
            if let battery = model.batteryTemp {
                Text("·")
                Text("Battery \(settings.format(battery, decimals: 0))")
            }
            Spacer()
            Text("Updates every \(settings.refreshInterval, format: .number) s")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

// MARK: - Cards

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }
}

extension View {
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        )
    }
}

// MARK: - Charts

struct TemperatureHistoryCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @State private var hoverTime: Date?

    var body: some View {
        SectionCard(title: "Temperature · last \(settings.historyMinutes) minutes", symbol: "thermometer.medium") {
            Chart {
                ForEach(model.history) { sample in
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("Temp", settings.display(sample.hottestCPU)),
                        series: .value("Series", "Hottest core")
                    )
                    .foregroundStyle(by: .value("Series", "Hottest core"))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("Temp", settings.display(sample.averageCPU)),
                        series: .value("Series", "CPU average")
                    )
                    .foregroundStyle(by: .value("Series", "CPU average"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if let gpu = sample.gpu {
                        LineMark(
                            x: .value("Time", sample.time),
                            y: .value("Temp", settings.display(gpu)),
                            series: .value("Series", "GPU")
                        )
                        .foregroundStyle(by: .value("Series", "GPU"))
                        .interpolationMethod(.catmullRom)
                    }
                }

                if let sample = model.history.nearest(to: hoverTime) {
                    RuleMark(x: .value("Time", sample.time))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            HoverTooltip(time: sample.time) {
                                Text("Avg \(settings.format(sample.averageCPU))")
                                Text("Hottest \(settings.format(sample.hottestCPU))")
                            }
                        }
                }
            }
            .chartForegroundStyleScale([
                "CPU average": Color.orange,
                "Hottest core": Color.red.opacity(0.7),
                "GPU": Color.purple,
            ])
            .chartYAxisLabel(settings.unit.symbol)
            .chartLegend(position: .top, alignment: .trailing)
            .chartHover($hoverTime)
            .frame(height: 190)
        }
    }
}

struct PerCoreCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SectionCard(title: "CPU die temperatures", symbol: "cpu") {
            if model.cpuSensors.isEmpty {
                Text("No CPU temperature sensors found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(model.cpuSensors) { sensor in
                    BarMark(
                        x: .value("Core", sensor.label),
                        y: .value("Temp", settings.display(sensor.celsius))
                    )
                    .foregroundStyle(tempColor(sensor.celsius).gradient)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(Int(settings.display(sensor.celsius)))°")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: 0...settings.display(maxScaleCelsius))
                .chartYAxisLabel(settings.unit.symbol)
                .frame(height: 180)
            }
        }
    }

    private var maxScaleCelsius: Double {
        max(100, (model.cpuSensors.map(\.celsius).max() ?? 0) + 10)
    }
}

struct FanCard: View {
    @EnvironmentObject private var model: VitalsModel

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
                VStack(spacing: 14) {
                    ForEach(model.fans) { fan in
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
                                    .contentTransition(.numericText())
                                Text("Target \(Int(fan.targetRPM)) rpm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Range \(Int(fan.minRPM))–\(Int(fan.maxRPM)) rpm")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            }
        }
    }

    private func gaugeValue(_ fan: SMC.Fan) -> Double {
        guard fan.maxRPM > 0 else { return 0 }
        return min(max(fan.rpm / fan.maxRPM, 0), 1)
    }
}

struct CPUUsageCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @State private var hoverTime: Date?

    var body: some View {
        SectionCard(title: "CPU usage · last \(settings.historyMinutes) minutes", symbol: "gauge.with.dots.needle.50percent") {
            Chart {
                ForEach(model.history) { sample in
                    AreaMark(
                        x: .value("Time", sample.time),
                        y: .value("%", sample.usage)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("%", sample.usage)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }

                if let sample = model.history.nearest(to: hoverTime) {
                    RuleMark(x: .value("Time", sample.time))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            HoverTooltip(time: sample.time) {
                                Text(String(format: "CPU %.0f%%", sample.usage))
                            }
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("%")
            .chartHover($hoverTime)
            .frame(height: 160)
        }
    }
}

struct TopProcessesCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Top processes", symbol: "list.bullet.rectangle") {
            if model.topProcesses.isEmpty {
                Text("Gathering…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
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
                    Spacer(minLength: 0)
                    Text("CPU per process · 100% = one core")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            }
        }
    }
}

struct BatteryCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SectionCard(title: "Battery", symbol: batterySymbol) {
            if let battery = model.battery {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(battery.percent))%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
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

    private var batterySymbol: String {
        guard let battery = model.battery else { return "battery.100percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
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

// MARK: - Chart hover support

/// Tracks the cursor over a chart's plot area and reports the date under it.
extension View {
    func chartHover(_ hoverTime: Binding<Date?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].origin.x
                            hoverTime.wrappedValue = proxy.value(atX: x)
                        case .ended:
                            hoverTime.wrappedValue = nil
                        }
                    }
            }
        }
    }
}

struct HoverTooltip<Rows: View>: View {
    let time: Date
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
            rows
        }
        .font(.caption2)
        .monospacedDigit()
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

extension Array where Element == VitalsModel.Sample {
    func nearest(to time: Date?) -> VitalsModel.Sample? {
        guard let time else { return nil }
        return self.min {
            abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time))
        }
    }
}

// MARK: - Helpers

/// Severity color; thresholds are always in °C regardless of display unit.
func tempColor(_ celsius: Double) -> Color {
    switch celsius {
    case ..<60: return .green
    case ..<80: return .orange
    default: return .red
    }
}

func gigabytes(_ bytes: UInt64) -> Double {
    Double(bytes) / 1_073_741_824
}
