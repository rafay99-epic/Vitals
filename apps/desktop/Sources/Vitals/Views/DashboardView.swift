import SwiftUI

/// The Overview: health hero, per-subsystem tiles (each drills into its Monitor
/// section), the multi-metric chart, power and fans, and top processes.
struct DashboardView: View {
    @Environment(VitalsModel.self) private var model
    let drill: (NavSection) -> Void

    var body: some View {
        ScrollView {
            Group {
                if !model.hasLoaded {
                    LoadingStateView(
                        title: "Reading sensors",
                        message: "Vitals is taking its first measurement of this Mac's temperatures, fans, and memory."
                    )
                } else if model.sensorsUnavailable {
                    EmptyStateView(
                        symbol: "sensor.tag.radiowaves.forward.fill",
                        tint: .orange,
                        title: "No sensor data",
                        message: "Vitals couldn't read this Mac's temperature, fan, or memory sensors. This usually means a virtual machine or restricted hardware access — readings will appear here once they're available."
                    )
                } else {
                    cards
                }
            }
            .padding(20)
        }
    }

    /// Lazy so the first frame and each resize frame only lay out on-screen cards.
    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            UpdateBanner()
            DashboardHealthHero(drill: drill)
            DashboardTileGrid(drill: drill)
            PerformanceHistoryCard()
            HStack(alignment: .top, spacing: 16) {
                PowerCard()
                FanCard()
            }
            DashboardProcessesCard()
            DashboardFooter()
        }
    }
}

private struct DashboardFooter: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
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
            if settings.isOnBattery {
                Text("on battery")
                Text("·")
            }
            if model.sensorsStalled {
                Label("Sensors not responding, readings paused", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("Updates every \(settings.effectiveRefreshInterval, format: .number) s")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
