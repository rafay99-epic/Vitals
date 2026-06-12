import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                UpdateBanner()
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
        .modifier(WindowBackdrop())
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
                tint: model.averageCPUTemp.map(tempGradientColor) ?? .secondary
            )
            StatCard(
                title: "Hottest Core",
                value: model.hottestCPUSensor.map { settings.format($0.celsius) } ?? "—",
                subtitle: model.hottestCPUSensor.map { "Sensor \($0.label)" } ?? "",
                symbol: "flame",
                tint: model.hottestCPUSensor.map { tempGradientColor($0.celsius) } ?? .secondary
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

/// Shown at the top of the dashboard while an update is available or installing.
struct UpdateBanner: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        switch updater.status {
        case .available(let release):
            banner {
                Label("Vitals \(release.version) is available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("You're on \(Updater.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install Update") {
                    Task { await updater.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .downloading:
            banner {
                Label("Downloading update…", systemImage: "arrow.down.circle")
                Spacer()
                ProgressView().controlSize(.small)
            }
        case .installing:
            banner {
                Label("Installing — Vitals will relaunch in a moment", systemImage: "gearshape.arrow.triangle.2.circlepath")
                Spacer()
                ProgressView().controlSize(.small)
            }
        default:
            EmptyView()
        }
    }

    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .font(.callout)
            .padding(12)
            .cardBackground()
    }
}
