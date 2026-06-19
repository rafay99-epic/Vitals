import SwiftUI

/// One sensor in the CPU die map — tinted by temperature. Shown in the per-core
/// disclosure inside `CPUCard`.
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
                .numericTransition()
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

/// The per-core CPU temperature heat grid + a coolest/hottest legend. Shared by
/// the Dashboard CPU card and the CPU tab so the two render the identical grid.
struct CoreTempGrid: View {
    @EnvironmentObject private var settings: AppSettings
    let sensors: [VitalsModel.Sensor]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(sensors) { DieCell(sensor: $0) }
            }
            legend
        }
    }

    @ViewBuilder
    private var legend: some View {
        let temps = sensors.map(\.celsius)
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
