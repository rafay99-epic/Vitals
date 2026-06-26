import SwiftUI

/// Shared mapping from a drive's wear severity to a gauge colour, so the Disk
/// tab and the Dashboard SSD card can never drift apart (and a flagged drive
/// shows orange/red, not green).
func diskWearTint(_ level: DiskHealthSnapshot.WearLevel) -> Color {
    switch level {
    case .normal:   return .green
    case .elevated: return .orange
    case .critical: return .red
    }
}

/// The Disk tab: the internal SSD's health, straight from its own NVMe SMART
/// log — wear, lifetime data written, power-on time, cycles, unsafe shutdowns,
/// spare blocks and temperature. Every figure is a counter the drive reports;
/// nothing is estimated or invented. A Mac (or VM) that doesn't expose SMART
/// says so rather than showing a fake "100% healthy".
struct DiskView: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        MetricScroll {
            if let disk = model.diskHealth {
                DiskHealthHeroCard(disk: disk)
                DiskEnduranceCard(disk: disk)
                DiskLifetimeCard(disk: disk)
            } else {
                EmptyStateView(
                    symbol: "internaldrive.badge.exclamationmark",
                    tint: .blue,
                    title: "SMART unavailable",
                    message: "This Mac doesn't expose detailed SSD health — some hardware, virtual machines, and external drives don't. When it's available, wear, data written and power-on history appear here."
                ) { EmptyView() }
            }
        }
    }
}

// MARK: - Wear / health hero

struct DiskHealthHeroCard: View {
    let disk: DiskHealthSnapshot

    var body: some View {
        SectionCard(title: "Drive health", symbol: "internaldrive.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(disk.percentUsed)%")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition()
                    Text("used").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        conditionBadge
                        if let identity = identityLine {
                            Text(identity).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Gauge(value: min(Double(disk.percentUsed) / 100, 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(diskWearTint(disk.wearLevel))
                Text("of the drive's rated write endurance — the drive's own estimate")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// "APPLE SSD AP0512Z · 512 GB" — whichever parts the drive reports.
    private var identityLine: String? {
        let parts = [disk.model, disk.capacityBytes.map { formatBytes(UInt64($0)) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var conditionBadge: some View {
        let ok = disk.criticalWarning == 0
        return Text(DiskHealthSnapshot.condition(criticalWarning: disk.criticalWarning))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill((ok ? Color.green : .orange).opacity(0.18)))
            .foregroundStyle(ok ? Color.green : .orange)
    }
}

// MARK: - Endurance (bytes written / read)

struct DiskEnduranceCard: View {
    let disk: DiskHealthSnapshot

    var body: some View {
        SectionCard(title: "Endurance", symbol: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatBytes(UInt64(disk.bytesWritten)))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition()
                    Text("written, lifetime").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                Divider()
                MetricRowGrid(rows: [
                    MetricRow(symbol: "square.and.arrow.up", label: "Data read", value: formatBytes(UInt64(disk.bytesRead))),
                    MetricRow(symbol: "shield.lefthalf.filled", label: "Spare blocks", value: "\(disk.availableSpare)%"),
                ])
            }
        }
    }
}

// MARK: - Lifetime counters

struct DiskLifetimeCard: View {
    @EnvironmentObject private var settings: AppSettings
    let disk: DiskHealthSnapshot

    var body: some View {
        SectionCard(title: "Lifetime", symbol: "clock.arrow.circlepath") {
            MetricRowGrid(rows: rows)
        }
    }

    private var rows: [MetricRow] {
        var rows: [MetricRow] = [
            MetricRow(symbol: "power", label: "Powered on", value: disk.poweredOnText),
            MetricRow(symbol: "arrow.triangle.2.circlepath", label: "Power cycles", value: "\(disk.powerCycles)"),
            MetricRow(symbol: "bolt.slash", label: "Unsafe shutdowns", value: "\(disk.unsafeShutdowns)"),
        ]
        if let temp = disk.temperature {
            rows.append(MetricRow(symbol: "thermometer.medium", label: "Temperature", value: settings.formatWithUnit(temp)))
        }
        // Surface media errors only if there are any — zero is the norm and
        // listing it just adds noise.
        if disk.mediaErrors > 0 {
            rows.append(MetricRow(symbol: "exclamationmark.triangle", label: "Media errors", value: "\(disk.mediaErrors)"))
        }
        return rows
    }
}
