import SwiftUI

/// Current GPU state: utilization hero, memory used/total, name. Apple Silicon
/// exposes no GPU-specific temperature sensor (CPU and GPU share one die, and
/// the die diodes aren't labeled by block), so temperature is deliberately not
/// shown here — the honesty rule forbids labelling a generic die reading "GPU".
struct GPUCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "GPU", symbol: "cpu.fill") {
            if let gpu = model.gpu {
                VStack(alignment: .leading, spacing: 12) {
                    header(gpu)
                    if gpu.memoryUsed != nil {
                        memoryBar(gpu)
                        memoryLegend(gpu)
                    }
                }
            } else {
                Text("GPU statistics unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func header(_ gpu: GPUSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(gpu.utilization.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericTransition()
            Text("utilization")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if let name = gpu.name {
                Text(name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memoryBar(_ gpu: GPUSnapshot) -> some View {
        GeometryReader { geometry in
            let fraction = gpu.memoryFraction ?? 0
            HStack(spacing: 1) {
                Color.purple
                    .frame(width: geometry.size.width * fraction)
                Color.secondary.opacity(0.15)  // free
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 14)
    }

    private func memoryLegend(_ gpu: GPUSnapshot) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Color.purple).frame(width: 9, height: 9)
            Text("Memory in use").foregroundStyle(.secondary)
            Spacer()
            Text(memoryText(gpu)).monospacedDigit()
        }
        .font(.caption)
    }

    private func memoryText(_ gpu: GPUSnapshot) -> String {
        guard let used = gpu.memoryUsed else { return "—" }
        if let total = gpu.memoryTotal, total > 0 {
            return String(format: "%.2f GB of %.0f GB", gigabytes(used), gigabytes(total))
        }
        return String(format: "%.2f GB", gigabytes(used))
    }
}
