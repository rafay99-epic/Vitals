import SwiftUI

/// The desktop widgets Vitals can float on screen. Each is a small panel that
/// reads the *same* live `VitalsModel` the dashboard uses — no separate logic.
enum WidgetKind: String, CaseIterable, Identifiable {
    case cpu
    case cpuUsage
    case gpu
    case memory
    case battery
    case fan
    case network
    case disk
    case storage
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU Temperature"
        case .cpuUsage: return "CPU Usage"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .fan: return "Fan"
        case .network: return "Network"
        case .disk: return "Disk I/O"
        case .storage: return "Storage"
        case .combined: return "Vitals"
        }
    }

    /// Short label for the icon-tile header inside the card.
    var shortTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .cpuUsage: return "CPU Usage"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .fan: return "Fan"
        case .network: return "Network"
        case .disk: return "Disk"
        case .storage: return "Storage"
        case .combined: return "Vitals"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .cpuUsage: return "gauge.with.dots.needle.50percent"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .battery: return "battery.100percent"
        case .fan: return "fan"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .storage: return "internaldrive"
        case .combined: return "gauge.with.dots.needle.50percent"
        }
    }

    /// The card's accent — used for the icon tile and sparkline. CPU/Memory
    /// override this dynamically (temperature / pressure color).
    var tint: Color {
        switch self {
        case .cpu: return .orange
        case .cpuUsage: return .blue
        case .gpu: return .purple
        case .memory: return .indigo
        case .battery: return .green
        case .fan: return .cyan
        case .network: return .mint
        case .disk: return .yellow
        case .storage: return .teal
        case .combined: return .green
        }
    }

    // Combined's heights grew with its Network row, then again with its Disk
    // row (5 metric rows on a GPU Mac). Saved frames are clamped to these
    // bounds on restore (`WidgetFrameStore` clamps every read), so existing
    // panels grow to fit rather than clipping the new row.
    var defaultSize: CGSize {
        self == .combined ? CGSize(width: 320, height: 240) : CGSize(width: 212, height: 118)
    }

    /// Resize bounds — a widget can't collapse to nothing or balloon off-screen.
    var minSize: CGSize {
        self == .combined ? CGSize(width: 280, height: 220) : CGSize(width: 178, height: 104)
    }

    var maxSize: CGSize {
        self == .combined ? CGSize(width: 560, height: 352) : CGSize(width: 380, height: 240)
    }
}
