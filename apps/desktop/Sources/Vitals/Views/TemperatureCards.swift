import SwiftUI
import Charts

struct TemperatureHistoryCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @State private var hoverTime: Date?

    var body: some View {
        SectionCard(title: "Temperature · last \(settings.historyMinutes) minutes", symbol: "thermometer.medium") {
            Deferred {
                Chart {
                ForEach(model.chartHistory) { sample in
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
            }
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
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], spacing: 6) {
                        ForEach(model.cpuSensors) { sensor in
                            DieCell(sensor: sensor)
                        }
                    }
                    summary
                }
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        let temps = model.cpuSensors.map(\.celsius)
        if let coolest = temps.min(), let hottest = temps.max() {
            let average = temps.reduce(0, +) / Double(temps.count)
            HStack(spacing: 12) {
                Text("Coolest \(settings.format(coolest, decimals: 0))")
                Text("Average \(settings.format(average, decimals: 0))")
                Text("Hottest \(settings.format(hottest, decimals: 0))")
                Spacer()
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tempGradientColor(40), tempGradientColor(60), tempGradientColor(75), tempGradientColor(90)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 96, height: 5)
                Text("\(settings.format(40, decimals: 0))–\(settings.format(90, decimals: 0))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

/// One sensor in the die map — tinted by temperature.
struct DieCell: View {
    let sensor: VitalsModel.Sensor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let tint = tempGradientColor(sensor.celsius)
        VStack(spacing: 2) {
            Text(sensor.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(settings.display(sensor.celsius).rounded()))°")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .help("\(sensor.label): \(settings.formatWithUnit(sensor.celsius))")
    }
}
