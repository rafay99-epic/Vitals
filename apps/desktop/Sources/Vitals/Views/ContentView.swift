import SwiftUI

/// Top-level navigation: a stationary header with segmented tabs over one
/// fixed content canvas — Activity Monitor style. There is no sidebar and no
/// window toolbar, so nothing can resize or snap the content, ever: tab
/// switches change what's drawn, never the geometry it's drawn in.
struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard, applications, cleanup, storage
        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .applications: return "Applications"
            case .cleanup: return "Cleanup"
            case .storage: return "Storage"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.50percent"
            case .applications: return "square.grid.2x2"
            case .cleanup: return "sparkles"
            case .storage: return "internaldrive"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .dashboard: return "1"
            case .applications: return "2"
            case .cleanup: return "3"
            case .storage: return "4"
            }
        }
    }

    @State private var section: Section = .dashboard
    @State private var gearHovered = false
    @Environment(\.openWindow) private var openWindow
    @Namespace private var tabIndicator
    // Owned here so the scans survive section switches — recreating these per
    // visit meant a full rescan (and a "Scanning…" flash) every time.
    @StateObject private var appsModel = AppsModel()
    @StateObject private var cleanupModel = CleanupModel()
    @StateObject private var storageModel = StorageModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.5)
            Group {
                switch section {
                case .dashboard: DashboardView()
                case .applications: AppsView(model: appsModel)
                case .cleanup: CleanupView(model: cleanupModel)
                case .storage: StorageView(model: storageModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The hidden title bar still reserves a safe-area strip; claim it so
        // the header shares the row with the traffic lights instead of
        // leaving a dead band above itself.
        .ignoresSafeArea(edges: .top)
        .modifier(WindowBackdrop())
        .frame(minWidth: 980, minHeight: 680)
    }

    // MARK: Header

    /// The title bar replacement: branding, centered tabs, settings — one
    /// row shared with the traffic lights. It also drags the window, since
    /// the system title bar is hidden.
    private var header: some View {
        ZStack {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                Text("Vitals")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.quaternary.opacity(gearHovered ? 0.7 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { gearHovered = hovering }
                }
                .help("Vitals settings")
            }
            tabBar
        }
        .padding(.leading, 84)  // clear the traffic lights
        .padding(.trailing, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Section.allCases) { item in
                tabButton(item)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    private func tabButton(_ item: Section) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                section = item
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(section == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if section == item {
                Capsule()
                    .fill(.quaternary)
                    .matchedGeometryEffect(id: "selected-tab", in: tabIndicator)
            }
        }
        .keyboardShortcut(item.shortcut, modifiers: .command)
        .help("\(item.title) (⌘\(item.shortcut.character))")
    }
}

/// The original live dashboard, unchanged — now one section of the window.
struct DashboardView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

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
                    ) {
                        EmptyView()
                    }
                } else {
                    glassBatched
                }
            }
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
        if #available(macOS 26.0, *), settings.glassEnabled {
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
        // Fixed columns, not adaptive: adaptive grids re-flow their column
        // count at every width, which made the cards snap around (and stall
        // the frame) on each step of the sidebar animation. Three flexible
        // columns scale smoothly at any width.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
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
