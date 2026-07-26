import Foundation
import SwiftUI

/// The metric choices are model-owned so HistoryView can be remounted without
/// losing the user's selection. Labels and symbols stay here because they are
/// also used by the controls and command-line launch override.
enum HistoryMetric: String, CaseIterable, Identifiable {
    case temp, cpu, gpu, memory, network, disk, battery, power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temp: return "Temp"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .disk: return "Disk"
        case .battery: return "Battery"
        case .power: return "Power"
        }
    }

    var symbol: String {
        switch self {
        case .temp: return "thermometer.medium"
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .battery: return "battery.100percent"
        case .power: return "bolt.fill"
        }
    }
}

/// State that must survive HistoryView's active-section lifecycle. The view is
/// intentionally remounted to release hidden SwiftUI/chart trees, while this
/// model keeps the selected range, metric, and loaded result available when the
/// user returns.
@MainActor
final class HistoryModel: ObservableObject {
    @Published var range: HistoryRange = .day
    @Published var metric: HistoryMetric = LaunchOverrides.historyMetric ?? .temp
    @Published private(set) var samples: [HistorySample] = []
    @Published private(set) var alertEvents: [AlertEvent] = []
    @Published private(set) var loading = false

    func reload() async {
        loading = true
        let selectedRange = range
        let result = await Task.detached(priority: .userInitiated) {
            (HistoryReader.load(range: selectedRange, now: Date()), AlertLog.recent(limit: 30))
        }.value
        guard !Task.isCancelled else {
            loading = false
            return
        }
        samples = result.0
        alertEvents = result.1
        loading = false
    }
}
