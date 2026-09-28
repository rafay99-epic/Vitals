import Foundation
import SwiftUI

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

/// History state that survives HistoryView being unmounted when another section
/// is selected.
@MainActor
@Observable
final class HistoryModel {
    var range: HistoryRange = .day
    var metric: HistoryMetric = LaunchOverrides.historyMetric ?? .temp
    private(set) var samples: [HistorySample] = []
    private(set) var alertEvents: [AlertEvent] = []
    private(set) var loading = false

    func reload() async {
        loading = true
        let selectedRange = range
        let result = await Task.detached(priority: .userInitiated) {
            (HistoryReader.load(range: selectedRange, now: Date()), AlertLog.recent(limit: 30))
        }.value
        // A newer request may already be loading; a cancelled one must not clear its spinner.
        guard !Task.isCancelled else { return }
        samples = result.0
        alertEvents = result.1
        loading = false
    }
}
