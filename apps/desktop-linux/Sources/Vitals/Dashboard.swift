import Adwaita
import Foundation
import VitalsCore

/// The single monitoring surface. Holds the latest `DashboardState` and refreshes
/// it on a timer; everything below is display-only.
///
/// Sampling runs in the `Idle` timer on the GLib main loop. Unlike macOS — where
/// the sensor sweep issues hundreds of slow syscalls and must go off-thread —
/// reading a handful of `/proc` and `/sys` pseudo-files costs microseconds, so a
/// 2-second main-loop tick never hitches the UI. (Revisit with a background queue
/// if profiling on real hardware ever shows otherwise.)
struct DashboardView: View {

    @State var ui = DashboardState()
    @State var started = false
    /// The running app, used to reopen the window from the tray.
    var app: GTUIApp!

    var view: Body {
        ScrollView {
            if !ui.hasLoaded {
                StatusPage(
                    "Reading sensors…",
                    icon: .default(icon: .applicationXExecutable),
                    description: "Gathering the first readings."
                ) { Text("") }
            } else if ui.sensorsUnavailable {
                StatusPage(
                    "No sensors",
                    icon: .default(icon: .applicationXExecutable),
                    description: "This system exposes no readable sensors — it may be a VM or a restricted host."
                ) { Text("") }
            } else {
                VStack {
                    HeroTiles(ui: ui)
                    ChartsSection(ui: ui)
                    Breakdowns(ui: ui)
                }
                .padding()
            }
        }
        .topToolbar {
            HeaderBar.empty()
                .headerBarTitle {
                    WindowTitle(subtitle: ui.hasLoaded ? ui.chipName : "", title: "Vitals")
                }
        }
        .onAppear {
            guard !started else { return }
            started = true
            TrayIcon.shared.start { app?.addWindow("main") }
            let first = VitalsModel.shared.next()
            ui = first
            TrayIcon.shared.update(first)
            Idle(delay: .seconds(2)) {
                let latest = VitalsModel.shared.next()
                ui = latest
                TrayIcon.shared.update(latest)
                return true
            }
        }
    }
}

/// The two rows of hero stat cards.
struct HeroTiles: View {
    let ui: DashboardState

    private var memoryValue: String {
        guard let m = ui.memory else { return "—" }
        return "\(Fmt.gigabytes(m.used)) / \(Fmt.gigabytes(m.total))"
    }
    private var fanValue: String {
        guard let fan = ui.fans.first else { return "Fanless" }
        return fan.rpm == 0 ? "Stopped" : "\(fan.rpm) rpm"
    }

    var view: Body {
        VStack {
            HStack {
                StatTile(title: "CPU Temp", value: Fmt.temp(ui.cpuTempAvg), subtitle: "average across cores")
                StatTile(title: "CPU Usage", value: Fmt.percent(ui.cpuUsage), subtitle: ui.chipName)
                StatTile(title: "Memory", value: memoryValue, subtitle: ui.pressure?.label ?? "in use / total")
            }
            HStack {
                StatTile(title: "Hottest Core", value: Fmt.temp(ui.hottestTemp), subtitle: ui.hottestLabel ?? "—")
                StatTile(title: "Fan", value: fanValue, subtitle: ui.fans.count > 1 ? "\(ui.fans.count) fans" : "speed")
                StatTile(title: "GPU", value: Fmt.temp(ui.gpuTemp), subtitle: ui.gpuTemp == nil ? "no sensor" : "graphics")
            }
        }
    }
}

/// The three history sparklines.
struct ChartsSection: View {
    let ui: DashboardState

    private var memoryValue: String {
        guard let m = ui.memory else { return "—" }
        return Fmt.gigabytes(m.used)
    }

    var view: Body {
        VStack {
            ChartCard(title: "Temperature", value: Fmt.temp(ui.hottestTemp ?? ui.cpuTempAvg), series: ui.tempHistory, color: .temp)
            ChartCard(title: "CPU Usage", value: Fmt.percent(ui.cpuUsage), series: ui.cpuHistory, color: .cpu)
            ChartCard(title: "Memory", value: memoryValue, series: ui.memHistory, color: .memory)
        }
    }
}

/// The breakdown cards: dies, fans, memory, processes, battery.
struct Breakdowns: View {
    let ui: DashboardState

    private var dieRows: [Row] {
        rows(ui.dieTemps.map { ($0.label, Fmt.temp($0.celsius)) })
    }
    private var fanRows: [Row] {
        rows(ui.fans.map { ($0.label, $0.rpm == 0 ? "Stopped" : "\($0.rpm) rpm") })
    }
    private var memoryRows: [Row] {
        guard let m = ui.memory else { return [] }
        var pairs: [(String, String)] = [
            ("Used", Fmt.gigabytes(m.used)),
            ("Available", Fmt.gigabytes(m.available)),
            ("Cached", Fmt.gigabytes(m.cached))
        ]
        if m.swapTotal > 0 {
            pairs.append(("Swap", "\(Fmt.gigabytes(m.swapUsed)) / \(Fmt.gigabytes(m.swapTotal))"))
        }
        if let pressure = ui.pressure {
            pairs.append(("Pressure", pressure.label))
        }
        return rows(pairs)
    }
    private var processRows: [Row] {
        rows(ui.topProcesses.map { ($0.name, Fmt.percent($0.cpuPercent)) })
    }
    private var batteryRows: [Row] {
        guard let b = ui.battery else { return [] }
        var pairs: [(String, String)] = [
            ("Charge", Fmt.percent(b.percent)),
            ("Status", b.status)
        ]
        if let health = b.healthPercent { pairs.append(("Health", Fmt.percent(health))) }
        if let cycles = b.cycleCount { pairs.append(("Cycles", "\(cycles)")) }
        if let watts = b.watts { pairs.append(("Power", Fmt.watts(watts))) }
        return rows(pairs)
    }

    var view: Body {
        VStack {
            InfoCard(title: "CPU Die Temperatures", entries: dieRows, emptyText: "No per-core sensors")
            InfoCard(title: "Fans", entries: fanRows, emptyText: "Fanless")
            InfoCard(title: "Memory", entries: memoryRows)
            InfoCard(title: "Top Processes", entries: processRows, emptyText: "Measuring…")
            if ui.battery != nil {
                InfoCard(title: "Battery", entries: batteryRows)
            }
        }
    }
}
