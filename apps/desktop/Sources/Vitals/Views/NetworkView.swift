import SwiftUI
import Charts

/// The Network section: summed download/upload, the throughput chart, the
/// per-interface breakdown (active first), and the Wi-Fi association.
struct NetworkView: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        MetricScroll {
            if let network = model.network {
                NetworkHeroCard(network: network)
                NetworkHistoryCard()
                NetworkInterfacesCard(links: network.links, primaryName: network.primaryInterfaceName)
                if let wifi = network.wifi {
                    WiFiCard(wifi: wifi)
                }
            } else {
                // A rate needs two readings, so the first tick shows "measuring", not 0.
                LoadingStateView(
                    title: "Measuring network throughput",
                    message: "A live rate is the difference between two readings a second apart — the first numbers land in a moment."
                )
            }
        }
    }
}

// MARK: - Heroes

private struct NetworkHeroCard: View {
    let network: NetworkSnapshot

    var body: some View {
        SectionCard(title: "Throughput", symbol: "arrow.up.arrow.down") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 28) {
                    hero("arrow.down", "Download", network.totalInPerSec, tint: .mint)
                    hero("arrow.up", "Upload", network.totalOutPerSec, tint: .orange)
                    Spacer(minLength: 0)
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hero(_ symbol: String, _ label: String, _ rate: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(NetworkFormat.rate(rate))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .numericTransition()
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// The primary link, e.g. "Wi-Fi (en0)": the default-route interface, else the
    /// first active link, else "No active interface".
    private var subtitle: String {
        guard let link = primaryLink else { return "No active interface" }
        return "\(link.displayName) (\(link.name))"
    }

    private var primaryLink: NetworkLink? {
        if let name = network.primaryInterfaceName,
           let link = network.links.first(where: { $0.name == name }) {
            return link
        }
        return network.links.first(where: { $0.isActive })
    }
}

// MARK: - Throughput history

private struct NetworkHistoryCard: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings
    private var chartHistory: [VitalsModel.Sample] { model.chartHistory }

    var body: some View {
        // One pass for the Y ceiling, outside the per-sample chart closure. A small
        // floor keeps an idle link off a zero-height axis. Rates are bytes/s; the
        // chart plots MB/s.
        let peak = chartHistory.reduce(0.0) { max($0, mbps($1.netInPerSec), mbps($1.netOutPerSec)) }
        let upper = max(peak * 1.15, 0.1)
        return SectionCard(title: "Last \(settings.historyMinutes) minutes", symbol: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                Deferred { chart(upper: upper) }.frame(height: 150)
                legend
            }
        }
    }

    private func chart(upper: Double) -> some View {
        Chart {
            ForEach(chartHistory) { sample in
                if let down = sample.netInPerSec {
                    AreaMark(x: .value("Time", sample.time),
                             y: .value("MB/s", down / 1_000_000),
                             series: .value("Series", "Download"))
                        .foregroundStyle(LinearGradient(colors: [.mint.opacity(0.35), .mint.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", sample.time),
                             y: .value("MB/s", down / 1_000_000),
                             series: .value("Series", "Download"))
                        .foregroundStyle(.mint)
                        .interpolationMethod(.catmullRom)
                }
                if let up = sample.netOutPerSec {
                    LineMark(x: .value("Time", sample.time),
                             y: .value("MB/s", up / 1_000_000),
                             series: .value("Series", "Upload"))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartYScale(domain: 0...upper)
        .chartYAxisLabel("MB/s")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            swatch(.mint, "Download")
            swatch(.orange, "Upload")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }

    private func mbps(_ bytesPerSec: Double?) -> Double { (bytesPerSec ?? 0) / 1_000_000 }
}

// MARK: - Interfaces

/// Every counted physical interface, active first. Totals are since-boot kernel
/// counters.
private struct NetworkInterfacesCard: View {
    let links: [NetworkLink]
    let primaryName: String?

    var body: some View {
        SectionCard(title: "Interfaces", symbol: "network") {
            if links.isEmpty {
                Text("No network interfaces.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(links, id: \.name) { link in
                        row(link)
                    }
                }
            }
        }
    }

    private func row(_ link: NetworkLink) -> some View {
        HStack(spacing: 12) {
            iconTile(link)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(link.displayName).font(.callout).fontWeight(.medium)
                    Text(link.name).font(.caption).foregroundStyle(.tertiary)
                    if link.name == primaryName { primaryTag }
                }
                Text("Since boot: ↓ \(NetworkFormat.bytes(link.totalBytesIn)) · ↑ \(NetworkFormat.bytes(link.totalBytesOut))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            trailing(link)
        }
    }

    private func iconTile(_ link: NetworkLink) -> some View {
        let tint: Color = link.isActive ? .mint : .secondary
        return Image(systemName: symbol(for: link.kind))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.14)))
    }

    private func symbol(for kind: NetworkLink.Kind) -> String {
        switch kind {
        case .wifi:     return "wifi"
        case .ethernet: return "cable.connector"
        case .other:    return "network"
        }
    }

    @ViewBuilder
    private func trailing(_ link: NetworkLink) -> some View {
        if link.isActive {
            Text("↓ \(NetworkFormat.rate(link.bytesInPerSec)) · ↑ \(NetworkFormat.rate(link.bytesOutPerSec))")
                .font(.system(.callout, design: .rounded, weight: .medium))
                .monospacedDigit()
                .numericTransition()
                .foregroundStyle(.secondary)
        } else {
            Text("Inactive")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private var primaryTag: some View {
        Text("Primary")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.mint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(.mint.opacity(0.15)))
    }
}

// MARK: - Wi-Fi

/// The Wi-Fi association. Every field is optional because the OS withholds
/// some: a nil SSID (no Location permission) shows a dash with a note, and
/// other unknown values drop their row.
private struct WiFiCard: View {
    let wifi: WiFiInfo

    var body: some View {
        SectionCard(title: "Wi-Fi", symbol: "wifi") {
            VStack(alignment: .leading, spacing: 12) {
                MetricRowGrid(rows: rows)
                if wifi.ssid == nil {
                    Text("macOS hides the network name from apps without Location access.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var rows: [MetricRow] {
        var rows = [MetricRow(symbol: "wifi", label: "Network", value: wifi.ssid ?? "—")]
        if let rssi = wifi.rssi {
            rows.append(MetricRow(symbol: "wave.3.right", label: "Signal", value: "\(rssi) dBm"))
        }
        if let noise = wifi.noise {
            rows.append(MetricRow(symbol: "waveform", label: "Noise", value: "\(noise) dBm"))
        }
        if let tx = wifi.txRateMbps {
            rows.append(MetricRow(symbol: "arrow.up.arrow.down", label: "Tx Rate", value: mbpsText(tx)))
        }
        if let channel = channelText {
            rows.append(MetricRow(symbol: "dot.radiowaves.left.and.right", label: "Channel", value: channel))
        }
        return rows
    }

    /// "36 · 5 GHz", or whichever half the OS reports; nil when it reports neither.
    private var channelText: String? {
        switch (wifi.channelNumber, wifi.channelBand) {
        case let (number?, band?): return "\(number) · \(band)"
        case let (number?, nil):   return "\(number)"
        case let (nil, band?):     return band
        case (nil, nil):           return nil
        }
    }

    /// Link rate with the trailing ".0" stripped ("866 Mbps", not "866.0 Mbps").
    private func mbpsText(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) Mbps" : String(format: "%.1f Mbps", value)
    }
}
