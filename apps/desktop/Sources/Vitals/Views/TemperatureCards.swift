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
