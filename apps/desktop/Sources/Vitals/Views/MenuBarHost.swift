import SwiftUI
import AppKit

/// The menu-bar status item's label — a **live** SwiftUI view hosted in a custom
/// `NSStatusItem` (see `MenuBarController`), not a rasterized image. Hosting it
/// live lets the fan/breath animation run on the Core Animation compositor: it's
/// driven at the display's own refresh rate (smooth on 120 Hz ProMotion), costs
/// no per-frame CPU, and renders as vectors (crisp at any display scale).
///
/// The status item is sized to this label's **intrinsic** width by the
/// controller (`MenuBarController.resize`), read off the hosting view — not from
/// an in-band measurement. `.fixedSize()` therefore matters: it pins the label to
/// its ideal footprint so that intrinsic width is stable and complete (issues
/// #45, #50).
struct MenuBarLabelView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    private var metrics: [MenuBarMetric] {
        MenuBarMetric.allCases.filter(settings.menuBarMetrics.contains)
    }
    private var warning: Bool {
        model.averageCPUTemp.map { $0 >= settings.warnThreshold } ?? false
    }

    var body: some View {
        content
            // Ideal size first: the row never compresses, so its glyphs can't
            // truncate. The controller then sizes the status item to this ideal.
            .fixedSize()
            .padding(.horizontal, 3)
            .frame(maxHeight: .infinity)            // fill the bar height, center vertically
            // labelColor resolves against the menu bar's appearance, so the
            // readout stays legible whether the bar is light or dark.
            .foregroundStyle(Color(nsColor: .labelColor))
    }

    @ViewBuilder
    private var content: some View {
        if metrics.isEmpty {
            Image(systemName: warning ? "flame.fill" : "thermometer.medium")
        } else if settings.menuBarUseIcons {
            MenuBarRow()
        } else {
            // Text style: short word + value, e.g. "Temp 57° · CPU 23% · RAM 12.8G".
            Text(metrics.map { "\($0.shortLabel) \(menuBarValue($0, model: model, settings: settings))" }
                .joined(separator: " · "))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The icon + value row. Reads the shared model/settings directly so its values
/// update reactively while the animation lives on.
private struct MenuBarRow: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    private var metrics: [MenuBarMetric] {
        MenuBarMetric.allCases.filter(settings.menuBarMetrics.contains)
    }
    private var warning: Bool {
        model.averageCPUTemp.map { $0 >= settings.warnThreshold } ?? false
    }
    // The animation is gated by `menuBarAnimationEnabled` (user opt-in + GPU
    // acceleration + not on battery/Low Power Mode). A status item isn't
    // GPU-composited like a window, so this repeating animation rasterizes every
    // frame on the CPU and runs continuously while shown — measured ~11% —
    // regardless of app focus. Worth it only when the user wants the motion and
    // the Mac isn't saving power; the numbers stay live either way.
    private var animate: Bool { settings.menuBarAnimationEnabled }

    /// 0 when the fan is stopped/unknown, toward 1 near its rated maximum.
    private var fanFraction: Double {
        guard let fan = model.fans.first, fan.rpm > 0 else { return 0 }
        let range = fan.maxRPM - fan.minRPM
        guard range > 0 else { return 0.5 }
        return min(max((fan.rpm - fan.minRPM) / range, 0), 1)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
                HStack(spacing: 3) {
                    MenuBarSymbol(metric: metric, warning: warning, index: index,
                                  animate: animate, fanFraction: fanFraction)
                    Text(menuBarValue(metric, model: model, settings: settings))
                        .monospacedDigit()
                        .lineLimit(1)   // a short value must stay on one line, never wrap (issue #45)
                }
            }
        }
        .font(.system(size: 13))
    }
}

/// One metric's symbol. The fan spins (speed eases up with rpm); the rest gently
/// breathe — both via repeating Core Animation, so the compositor renders them
/// at the display's refresh rate with no per-frame work. Mirrors the desktop
/// widgets' `WidgetIconTile`.
private struct MenuBarSymbol: View {
    let metric: MenuBarMetric
    let warning: Bool
    let index: Int
    let animate: Bool
    let fanFraction: Double

    @State private var angle: Double = 0
    @State private var breathing = false

    private var symbol: String { metric == .cpuTemp && warning ? "flame.fill" : metric.symbol }
    private var spinning: Bool { metric == .fan && animate && fanFraction > 0 }
    private var breathes: Bool { metric != .fan && animate }

    /// Seconds per revolution: ~3.6s near idle down to ~0.6s at rated RPM.
    private var period: Double { 3.6 - 3.0 * min(max(fanFraction, 0), 1) }
    /// Restart the spin only when the speed bucket (or the animate flag) changes.
    private var spinKey: String { "\(animate)-\(Int((fanFraction * 100).rounded()))" }

    var body: some View {
        Image(systemName: symbol)
            .rotationEffect(.degrees(metric == .fan ? angle : 0))
            .scaleEffect(breathes && breathing ? 1.06 : 1.0)
            .animation(breathes ? .easeInOut(duration: 2.0 + Double(index) * 0.25).repeatForever(autoreverses: true)
                                : .default,
                       value: breathing)
            .task(id: spinKey) { restartSpin() }
            .onAppear { breathing = true }
    }

    private func restartSpin() {
        withAnimation(.linear(duration: 0)) { angle = 0 } // snap to rest first
        guard spinning else { return }
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}

/// The live reading for one metric. A dash (never a fabricated value) stands in
/// when a subsystem isn't present or hasn't reported yet.
@MainActor
func menuBarValue(_ metric: MenuBarMetric, model: VitalsModel, settings: AppSettings) -> String {
    switch metric {
    case .cpuTemp:  return model.averageCPUTemp.map { settings.format($0, decimals: 0) } ?? "–"
    case .cpuUsage: return "\(Int(model.cpuUsage.rounded()))%"
    case .gpuUsage: return model.gpu?.utilization.map { "\(Int($0.rounded()))%" } ?? "–"
    case .memory:   return model.memory.map { String(format: "%.1fG", Double($0.used) / 1_073_741_824) } ?? "–"
    case .fan:      return model.fans.first.map { "\(Int($0.rpm))" } ?? "–"
    }
}
