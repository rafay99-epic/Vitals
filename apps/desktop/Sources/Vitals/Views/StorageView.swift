import SwiftUI

/// The internal SSD's SMART report: wear, endurance, TRIM, lifetime. A VM or
/// external-only setup gets an explicit empty state, never a fabricated "100%".
struct StorageView: View {
    @EnvironmentObject private var vitals: VitalsModel

    var body: some View {
        if let disk = vitals.diskHealth {
            MetricScroll {
                DiskHealthHeroCard(disk: disk)
                DiskEnduranceCard(disk: disk)
                DiskLifetimeCard(disk: disk)
            }
        } else {
            EmptyStateView(
                symbol: "internaldrive.badge.exclamationmark",
                tint: .blue,
                title: "SSD health unavailable",
                message: "This Mac doesn't expose detailed SSD health. Some hardware, virtual machines, and external drives don't. When it's available, wear, endurance, TRIM and power-on history appear here."
            ) { EmptyView() }
        }
    }
}
