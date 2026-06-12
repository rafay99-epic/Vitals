import SwiftUI

/// Top-level navigation: the live dashboard plus the app-management tools.
struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard, applications, cleanup
        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .applications: return "Applications"
            case .cleanup: return "Cleanup"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.50percent"
            case .applications: return "square.grid.2x2"
            case .cleanup: return "sparkles"
            }
        }
    }

    @State private var section: Section? = .dashboard
    @Environment(\.openWindow) private var openWindow
    // Owned here so the scans survive section switches — recreating these per
    // visit meant a full rescan (and a "Scanning…" flash) every time.
    @StateObject private var appsModel = AppsModel()
    @StateObject private var cleanupModel = CleanupModel()

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch section ?? .dashboard {
            case .dashboard: DashboardView()
            case .applications: AppsView(model: appsModel)
            case .cleanup: CleanupView(model: cleanupModel)
            }
        }
        .modifier(WindowBackdrop())
        .frame(minWidth: 980, minHeight: 680)
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
}

/// The original live dashboard, unchanged — now one section of the window.
struct DashboardView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            glassBatched
                .padding(20)
        }
    }

    /// On macOS 26 with Liquid Glass on, every card is its own glass surface
    /// — a dozen independent backdrop captures re-rendered each frame of the
    /// sidebar/window animation. GlassEffectContainer batches them into one
    /// render pass, which is most of the "freeze before it moves" fix.
    @ViewBuilder
    private var glassBatched: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), settings.liquidGlass {
            GlassEffectContainer {
                cards
            }
        } else {
            cards
        }
        #else
        cards
        #endif
    }

    /// Lazy so the window's first frame (and every frame of a resize
    /// animation) only builds and lays out the cards actually on screen —
    /// the heavy below-the-fold charts no longer tax open/close/toggle.
    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
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
            MemoryCard()
            MemoryHistoryCard()
            BatteryCard()
            footer
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
                value: String(format: "%.1f GB", gigabytes(model.memory?.used ?? 0)),
                subtitle: memorySubtitle,
                symbol: "memorychip",
                tint: model.memory.map { pressureColor($0.pressure) } ?? .indigo
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

    private var memorySubtitle: String {
        guard let memory = model.memory else { return "—" }
        return String(format: "of %.0f GB · %@ pressure", gigabytes(memory.total), memory.pressure.label)
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
