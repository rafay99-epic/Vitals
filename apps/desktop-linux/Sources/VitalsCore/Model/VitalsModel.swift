import Foundation

/// Everything the dashboard renders in one tick, derived from a `Snapshot` plus
/// rolling history. A plain value type so a view can hold it in `@State`; the
/// view never sees the raw services. Mirrors the published surface of the macOS
/// `VitalsModel`.
public struct DashboardState: Equatable, Sendable {
    public var hasLoaded = false
    /// True only when a sample landed but carried nothing usable (a VM / locked-
    /// down host) — drives an honest "no sensors" empty state.
    public var sensorsUnavailable = false
    public var chipName = "Processor"

    public var cpuTempAvg: Double?
    public var hottestLabel: String?
    public var hottestTemp: Double?
    public var gpuTemp: Double?
    public var cpuUsage: Double?

    public var memory: MemorySnapshot?
    public var pressure: MemoryPressure?

    public var fans: [FanReading] = []
    public var dieTemps: [TempReading] = []
    public var topProcesses: [ProcessUsage] = []
    public var battery: BatterySnapshot?

    // Downsampled series for the sparklines.
    public var tempHistory: [Double] = []
    public var cpuHistory: [Double] = []
    public var memHistory: [Double] = []

    public init() {}
}

/// Owns the sampler and the history buffer, and turns each sample into a
/// `DashboardState`. A single shared instance persists across view renders so
/// the CPU/process deltas (which need the previous tick) survive — the view
/// just calls `next()` on a timer.
public final class VitalsModel {

    public static let shared = VitalsModel()

    struct Point: Equatable { let temp: Double; let cpu: Double; let mem: Double }

    private let sampler = LinuxSensorSampler()
    private var history: [Point] = []
    /// ~20 minutes at a 2 s interval; the chart never draws more than it can show.
    static let maxHistory = 600
    static let chartPoints = 160

    public init() {}

    /// Takes one sample and returns the state to display. Call on the UI loop.
    public func next() -> DashboardState {
        Self.derive(sampler.sample(), history: &history)
    }

    /// Pure derivation, split out so it's unit-tested with synthetic snapshots.
    static func derive(_ snap: Snapshot, history: inout [Point]) -> DashboardState {
        var state = DashboardState()
        state.hasLoaded = true
        state.chipName = snap.chipName ?? "Processor"

        let cpuTemps = snap.temps.filter { $0.kind == .cpu }
        state.dieTemps = cpuTemps
        if !cpuTemps.isEmpty {
            state.cpuTempAvg = cpuTemps.map(\.celsius).reduce(0, +) / Double(cpuTemps.count)
        }
        if let hottest = cpuTemps.max(by: { $0.celsius < $1.celsius }) {
            state.hottestLabel = hottest.label
            state.hottestTemp = hottest.celsius
        }
        state.gpuTemp = average(snap.temps, kind: .gpu)
        state.cpuUsage = snap.cpuUsage
        state.memory = snap.memory
        state.pressure = snap.pressure
        state.fans = snap.fans
        state.topProcesses = snap.topProcesses
        state.battery = snap.battery
        state.sensorsUnavailable = snap.temps.isEmpty && snap.fans.isEmpty && snap.memory == nil

        // Append a history point once there's a temperature reference and a usage
        // reading (usage is nil on the very first tick — no delta yet).
        if let usage = snap.cpuUsage, let tempRef = state.hottestTemp ?? state.cpuTempAvg {
            let point = Point(temp: tempRef, cpu: usage, mem: Double(snap.memory?.used ?? 0))
            history.append(point)
            if history.count > maxHistory {
                history.removeFirst(history.count - maxHistory)
            }
        }
        let points = ChartMath.downsample(history, to: chartPoints)
        state.tempHistory = points.map(\.temp)
        state.cpuHistory = points.map(\.cpu)
        state.memHistory = points.map(\.mem)
        return state
    }

    private static func average(_ temps: [TempReading], kind: TempReading.Kind) -> Double? {
        let values = temps.filter { $0.kind == kind }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
