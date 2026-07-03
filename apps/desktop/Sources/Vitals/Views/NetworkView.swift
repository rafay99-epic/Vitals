import SwiftUI
import Charts

/// The Network tab: live throughput, the interfaces actually carrying traffic,
/// Wi-Fi radio detail when applicable, and session totals since launch. Every
/// number traces to `NetworkSampler` — an idle link honestly reads 0 B/s, and a
/// field CoreWLAN won't hand over (SSID under Location gating, RSSI before
/// association) shows "—" rather than a fabricated value.
struct NetworkView: View {
    @EnvironmentObject private var model: VitalsModel
    /// True only while the Network tab is the visible one — gates the history
    /// chart so a kept-mounted background tab doesn't rebuild marks every tick
    /// (mirrors GPUView/BatteryView).
    let isActive: Bool

    var body: some View {
        MetricScroll {
            NetworkHeroCard()
            if isActive, model.chartHistory.contains(where: { $0.downBps != nil || $0.upBps != nil }) {
                NetworkThroughputCard()
            }
            NetworkInterfacesCard()
            if let wifi = model.network?.wifi {
                NetworkWifiCard(wifi: wifi)
            }
            NetworkSessionCard()
        }
    }
}

// MARK: - Hero

private struct NetworkHeroCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Network", symbol: "network") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 28) {
                    rateColumn(symbol: "arrow.down", tint: .blue, value: model.network.map { byteRateText($0.downBps) })
                    rateColumn(symbol: "arrow.up", tint: .orange, value: model.network.map { byteRateText($0.upBps) })
                    Spacer()
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rateColumn(symbol: String, tint: Color, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value ?? "—")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericTransition()
        }
    }

    /// Primary interface + kind ("en0 · Wi-Fi") when the OS's primary interface
    /// is among the active ones; falls back to the first active interface (the
    /// primary can be a stale/offline entry while another link carries traffic)
    /// rather than fabricating an association. Honestly empty when nothing's active.
    private var subtitle: String {
        guard let network = model.network, !network.interfaces.isEmpty else { return "No active interfaces" }
        if let primaryName = network.primaryInterface,
           let match = network.interfaces.first(where: { $0.name == primaryName }) {
            return "\(match.name) · \(kindLabel(match.kind))"
        }
        if let first = network.interfaces.first {
            return "\(first.name) · \(kindLabel(first.kind))"
        }
        return "No active interfaces"
    }
}

// MARK: - Throughput history

private struct NetworkThroughputCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Throughput", symbol: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                // Deferred keeps the 50–150 ms first-layout Charts cost off the
                // tab-switch animation (see BatteryHistoryCard).
                Deferred { chart }.frame(height: 150)
                legend
            }
        }
    }

    private var chart: some View {
        Chart(model.chartHistory) { sample in
            if let down = sample.downBps {
                AreaMark(x: .value("Time", sample.time), y: .value("Download", down))
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.time), y: .value("Download", down))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
            }
            if let up = sample.upBps {
                AreaMark(x: .value("Time", sample.time), y: .value("Upload", up))
                    .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.30), .orange.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.time), y: .value("Upload", up))
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bps = value.as(Double.self) {
                        Text(byteRateText(max(0, bps)))
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendSwatch(.blue, "Download")
            legendSwatch(.orange, "Upload")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }
}

// MARK: - Interfaces

private struct NetworkInterfacesCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Interfaces", symbol: "point.3.connected.trianglepath.dotted") {
            let interfaces = model.network?.interfaces ?? []
            if interfaces.isEmpty {
                Text("No active interfaces")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(interfaces.enumerated()), id: \.element.id) { index, interface in
                        InterfaceRow(interface: interface)
                        if index < interfaces.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct InterfaceRow: View {
    let interface: NetworkSnapshot.InterfaceStats

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(interface.name).font(.callout.weight(.medium))
                Text(kindLabel(interface.kind)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                rateLine(symbol: "arrow.down", value: interface.downBps)
                rateLine(symbol: "arrow.up", value: interface.upBps)
            }
        }
    }

    private func rateLine(symbol: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text(byteRateText(value))
                .font(.system(.caption, design: .rounded, weight: .medium))
                .monospacedDigit()
                .numericTransition()
        }
        .foregroundStyle(.secondary)
    }

    private var symbol: String {
        switch interface.kind {
        case .wifi:     return "wifi"
        case .ethernet: return "cable.connector"
        case .vpn:      return "lock.shield"
        case .other:    return "network"
        }
    }

    private var tint: Color {
        switch interface.kind {
        case .wifi:     return .blue
        case .ethernet: return .teal
        case .vpn:      return .purple
        case .other:    return .gray
        }
    }
}

/// Human label for an interface kind — shared by the hero subtitle and the
/// interfaces list so they can't drift ("VPN" always reads as "VPN", never
/// a raw `utun4` name standing in for it).
private func kindLabel(_ kind: NetworkSnapshot.InterfaceKind) -> String {
    switch kind {
    case .wifi:     return "Wi-Fi"
    case .ethernet: return "Ethernet"
    case .vpn:      return "VPN"
    case .other:    return "Other"
    }
}

// MARK: - Wi-Fi

private struct NetworkWifiCard: View {
    let wifi: NetworkSnapshot.WifiInfo

    var body: some View {
        SectionCard(title: "Wi-Fi", symbol: "wifi") {
            MetricRowGrid(rows: rows)
        }
    }

    private var rows: [MetricRow] {
        [
            MetricRow(symbol: "wifi", label: "Network", value: wifi.ssid ?? "—"),
            MetricRow(symbol: "antenna.radiowaves.left.and.right",
                      label: "Signal", value: wifi.rssi.map { "\($0) dBm" } ?? "—"),
            MetricRow(symbol: "speedometer", label: "Tx rate",
                      value: wifi.txRateMbps.map { String(format: "%.0f Mb/s", $0) } ?? "—"),
            MetricRow(symbol: "number", label: "Channel", value: wifi.channel.map { "\($0)" } ?? "—")
        ]
    }
}

// MARK: - Session

private struct NetworkSessionCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Session", symbol: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    statColumn("Downloaded", downloadedText)
                    statColumn("Uploaded", uploadedText)
                    Spacer()
                }
                Text("Since Vitals launched — resets when the app restarts.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var downloadedText: String {
        guard let network = model.network else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(network.sessionDownBytes), countStyle: .file)
    }

    private var uploadedText: String {
        guard let network = model.network else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(network.sessionUpBytes), countStyle: .file)
    }
}
