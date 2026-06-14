import SwiftUI

/// Boot-volume capacity. Uses the same `StorageAnalyzer.volumeUsage()` the
/// Storage tab uses — an instant statfs-style read, refreshed every 30s via a
/// timeline (no heavy disk scan, no dependency on the Storage tab's model).
struct StorageWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            card(StorageAnalyzer.volumeUsage())
        }
    }

    private func card(_ usage: StorageAnalyzer.VolumeUsage?) -> some View {
        WidgetCard(title: "Storage", symbol: "internaldrive", tint: .teal,
                   intensity: usage?.usedFraction ?? 0) {
            if let usage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatBytes(usage.used))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("used")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                capacityBar(usage.usedFraction)
                Text("\(formatBytes(usage.free)) free of \(formatBytes(usage.total))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Disk unavailable")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func capacityBar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.5))
                Capsule().fill(.teal)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 5)
    }
}
