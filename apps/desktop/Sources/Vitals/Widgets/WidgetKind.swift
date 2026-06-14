import SwiftUI

/// The desktop widgets Vitals can float on screen. Each is a small panel that
/// reads the *same* live `VitalsModel` the dashboard uses — no separate logic.
enum WidgetKind: String, CaseIterable, Identifiable {
    case cpu
    case cpuUsage
    case memory
    case fan
    case storage
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU Temperature"
        case .cpuUsage: return "CPU Usage"
        case .memory: return "Memory"
        case .fan: return "Fan"
        case .storage: return "Storage"
        case .combined: return "Vitals"
        }
    }

    /// Short label for the icon-tile header inside the card.
    var shortTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .cpuUsage: return "CPU Usage"
        case .memory: return "Memory"
        case .fan: return "Fan"
        case .storage: return "Storage"
        case .combined: return "Vitals"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .cpuUsage: return "gauge.with.dots.needle.50percent"
        case .memory: return "memorychip"
        case .fan: return "fan"
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
        case .memory: return .indigo
        case .fan: return .cyan
        case .storage: return .teal
        case .combined: return .green
        }
    }

    var defaultSize: CGSize {
        self == .combined ? CGSize(width: 320, height: 132) : CGSize(width: 212, height: 118)
    }

    /// Resize bounds — a widget can't collapse to nothing or balloon off-screen.
    var minSize: CGSize {
        self == .combined ? CGSize(width: 280, height: 120) : CGSize(width: 178, height: 104)
    }

    var maxSize: CGSize {
        self == .combined ? CGSize(width: 560, height: 280) : CGSize(width: 380, height: 240)
    }
}
