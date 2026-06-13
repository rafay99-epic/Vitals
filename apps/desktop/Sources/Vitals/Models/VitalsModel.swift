import Foundation
import SwiftUI
import Combine

@MainActor
final class VitalsModel: ObservableObject {
    struct Sensor: Identifiable {
        enum Kind { case cpu, gpu, storage, battery, other }
        let id: String
        let label: String
        let kind: Kind
        let celsius: Double
    }

    struct Sample: Identifiable {
        let id: Date
        let time: Date
        let averageCPU: Double
        let hottestCPU: Double
        let gpu: Double?
        let usage: Double
        let memoryUsed: Double  // bytes
        let swapUsed: Double    // bytes
    }

    @Published private(set) var cpuSensors: [Sensor] = []
    @Published private(set) var gpuTemp: Double?
    @Published private(set) var ssdTemp: Double?
    @Published private(set) var batteryTemp: Double?
    @Published private(set) var fans: [SMC.Fan] = []
    @Published private(set) var hasSMC = false
    @Published private(set) var history: [Sample] = []
    /// `history` thinned for drawing — charts can't show more points than
    /// pixels, and Swift Charts rebuild cost scales with mark count.
    @Published private(set) var chartHistory: [Sample] = []
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memory: MemorySnapshot?
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var topProcesses: [ProcessSampler.Process] = []
    @Published private(set) var battery: BatterySnapshot?
    /// False until the first sample lands — drives the dashboard loading state.
    @Published private(set) var hasLoaded = false

    let memoryTotal = ProcessInfo.processInfo.physicalMemory

    /// True only when a sample arrived but carried no usable readings at all
    /// (no temps, no fans, no memory) — e.g. a VM or restricted hardware.
    /// On real Macs memory always reads, so this stays false.
    var sensorsUnavailable: Bool {
        hasLoaded && cpuSensors.isEmpty && gpuTemp == nil && !hasSMC && memory == nil
    }

    var averageCPUTemp: Double? {
        guard !cpuSensors.isEmpty else { return nil }
        return cpuSensors.map(\.celsius).reduce(0, +) / Double(cpuSensors.count)
    }

    var hottestCPUSensor: Sensor? {
        cpuSensors.max { $0.celsius < $1.celsius }
    }

    private let settings: AppSettings
    private let sampler = SensorSampler()
    private let notifications = NotificationManager()
    private let logger = HistoryLogger()
    private var timer: Timer?
    private var isSampling = false
    private var cancellables: Set<AnyCancellable> = []
    private static let maxChartPoints = 300

    // Overheat alerting state.
    private var hotSince: Date?
    private var lastHeatAlert: Date = .distantPast
    private var previousThermalState = ProcessInfo.processInfo.thermalState
    private static let heatAlertAfter: TimeInterval = 120
    private static let heatAlertCooldown: TimeInterval = 600

    init(settings: AppSettings) {
        self.settings = settings
        settings.$refreshInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.restartTimer() }
            .store(in: &cancellables)
        settings.$historyMinutes
            .dropFirst()
            .sink { [weak self] _ in self?.trimHistory() }
            .store(in: &cancellables)
        // Ask for notification permission as soon as any alert is enabled.
        settings.$notifyOverheat
            .merge(with: settings.$notifyThermal)
            .filter { $0 }
            .sink { [weak self] _ in self?.notifications.requestAuthorizationIfNeeded() }
            .store(in: &cancellables)
    }

    private var maxHistory: Int {
        max(2, Int(Double(settings.historyMinutes) * 60.0 / settings.refreshInterval))
    }

    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = settings.refreshInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        start()
    }

    private func trimHistory() {
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        chartHistory = Self.downsample(history, to: Self.maxChartPoints)
    }

    /// Kicks off one sample on the sampler's executor and publishes the
    /// result back here. `isSampling` drops a tick rather than letting a
    /// slow sample (heavily loaded machine) queue up behind itself.
    private func tick() {
        guard !isSampling else { return }
        isSampling = true
        Task {
            let snapshot = await sampler.sample()
            apply(snapshot)
            isSampling = false
        }
    }

    private func apply(_ snapshot: SensorSampler.Snapshot) {
        let classified = Self.classify(snapshot.readings)

        cpuSensors = classified.filter { $0.kind == .cpu }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        gpuTemp = Self.average(of: classified, kind: .gpu)
        ssdTemp = Self.average(of: classified, kind: .storage)
        batteryTemp = Self.average(of: classified, kind: .battery)
        fans = snapshot.fans
        hasSMC = snapshot.hasSMC
        thermalState = ProcessInfo.processInfo.thermalState
        if let usage = snapshot.cpuUsage { cpuUsage = usage }
        memory = snapshot.memory
        topProcesses = snapshot.topProcesses
        battery = snapshot.battery
        hasLoaded = true

        if let average = averageCPUTemp, let hottest = hottestCPUSensor {
            history.append(Sample(
                id: Date(),
                time: Date(),
                averageCPU: average,
                hottestCPU: hottest.celsius,
                gpu: gpuTemp,
                usage: cpuUsage,
                memoryUsed: Double(memory?.used ?? 0),
                swapUsed: Double(memory?.swapUsed ?? 0)
            ))
            trimHistory()

            checkAlerts(averageTemp: average)

            if settings.loggingEnabled {
                logger.append(
                    averageTemp: average,
                    hottestTemp: hottest.celsius,
                    gpuTemp: gpuTemp,
                    fanRPM: fans.first?.rpm,
                    cpuUsage: cpuUsage,
                    memoryUsedGB: gigabytes(memory?.used ?? 0),
                    thermalState: thermalState.label,
                    batteryPercent: battery?.percent
                )
            }
        }
    }

    /// Overheat: average CPU above the warning threshold for 2 minutes
    /// straight (10-minute cooldown between alerts). Thermal pressure:
    /// immediately, whenever macOS escalates to Serious or Critical.
    private func checkAlerts(averageTemp: Double) {
        if settings.notifyOverheat {
            if averageTemp >= settings.warnThreshold {
                if hotSince == nil { hotSince = Date() }
                if let since = hotSince,
                   Date().timeIntervalSince(since) >= Self.heatAlertAfter,
                   Date().timeIntervalSince(lastHeatAlert) >= Self.heatAlertCooldown {
                    notifications.send(
                        title: "Your Mac is running hot",
                        body: "Average CPU temperature has stayed above \(settings.format(settings.warnThreshold, decimals: 0)) for over 2 minutes — currently \(settings.formatWithUnit(averageTemp)).",
                        id: "vitals.overheat"
                    )
                    lastHeatAlert = Date()
                }
            } else {
                hotSince = nil
            }
        }

        if settings.notifyThermal,
           thermalState == .serious || thermalState == .critical,
           thermalState.rawValue > previousThermalState.rawValue {
            notifications.send(
                title: "Thermal pressure is \(thermalState.label)",
                body: "macOS is throttling performance to cool down. Consider quitting heavy apps — check Top Processes in Vitals.",
                id: "vitals.thermal"
            )
        }
        previousThermalState = thermalState
    }

    /// Evenly thins `samples` to at most `maxCount` points, always keeping
    /// the first and the newest. Indices step by more than one whenever
    /// thinning happens, so no sample (or id) repeats.
    static func downsample(_ samples: [Sample], to maxCount: Int) -> [Sample] {
        guard samples.count > maxCount, maxCount > 1 else { return samples }
        let stride = Double(samples.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { samples[Int((Double($0) * stride).rounded())] }
    }

    private static func average(of sensors: [Sensor], kind: Sensor.Kind) -> Double? {
        let values = sensors.filter { $0.kind == kind }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func classify(_ readings: [HIDSensors.Reading]) -> [Sensor] {
        var labelCounts: [String: Int] = [:]
        return readings.map { reading in
            let kind = kind(for: reading.name)
            var label = shortLabel(for: reading.name, kind: kind)
            // Disambiguate sensors that map to the same short label.
            let seen = labelCounts[label, default: 0]
            labelCounts[label] = seen + 1
            if seen > 0 { label += " (\(seen + 1))" }
            return Sensor(id: reading.name + "#\(seen)", label: label, kind: kind, celsius: reading.celsius)
        }
    }

    private static func kind(for name: String) -> Sensor.Kind {
        let n = name.lowercased()
        if n.contains("pacc") || n.contains("eacc") || n.contains("tdie") || n.contains("cpu") { return .cpu }
        if n.contains("gpu") { return .gpu }
        if n.contains("nand") || n.contains("ssd") { return .storage }
        if n.contains("battery") || n.contains("gas gauge") { return .battery }
        return .other
    }

    private static func shortLabel(for name: String, kind: Sensor.Kind) -> String {
        let number = name.reversed().prefix(while: \.isNumber).reversed().map(String.init).joined()
        let n = name.lowercased()
        switch kind {
        case .cpu:
            if n.contains("pacc") { return "P\(number)" }
            if n.contains("eacc") { return "E\(number)" }
            // M-series dies report as "PMU tdieN" / "PMU2 tdieN" — two banks.
            if n.contains("tdie") { return n.contains("pmu2") ? "B\(number)" : "A\(number)" }
            return name
        case .gpu: return number.isEmpty ? "GPU" : "GPU \(number)"
        case .storage: return "SSD"
        case .battery: return "Battery"
        case .other: return name
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}
