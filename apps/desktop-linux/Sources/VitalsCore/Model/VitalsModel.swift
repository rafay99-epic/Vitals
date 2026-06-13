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

    /// Independent rolling series, one per chart. Keeping them separate means a
    /// machine with no temperature sensor (e.g. a VM) still gets live CPU and
    /// memory charts — they never gate each other.
    struct History: Equatable {
        var temp: [Double] = []
        var cpu: [Double] = []
        var mem: [Double] = []
    }

    private let sampler = LinuxSensorSampler()
    private var history = History()
    /// ~20 minutes at a 2 s interval; the chart never draws more than it can show.
    static let maxHistory = 600
    static let chartPoints = 160

    public init() {}

    /// Takes one sample and returns the state to display. Call on the UI loop.
    public func next() -> DashboardState {
        Self.derive(sampler.sample(), history: &history)
    }

    /// Pure derivation, split out so it's unit-tested with synthetic snapshots.
    static func derive(_ snap: Snapshot, history: inout History) -> DashboardState {
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

        // Each series accumulates independently from its own signal. CPU usage is
        // nil on the very first tick (no delta yet), so its series just starts one
        // tick later; temperature and memory start immediately when present.
        if let tempRef = state.hottestTemp ?? state.cpuTempAvg { append(&history.temp, tempRef) }
        if let usage = snap.cpuUsage { append(&history.cpu, usage) }
        if let mem = snap.memory { append(&history.mem, Double(mem.used)) }

        state.tempHistory = ChartMath.downsample(history.temp, to: chartPoints)
        state.cpuHistory = ChartMath.downsample(history.cpu, to: chartPoints)
        state.memHistory = ChartMath.downsample(history.mem, to: chartPoints)
        return state
    }

    /// Appends to a rolling series, trimming to `maxHistory` from the front.
    private static func append(_ series: inout [Double], _ value: Double) {
        series.append(value)
        if series.count > maxHistory { series.removeFirst(series.count - maxHistory) }
    }

    private static func average(_ temps: [TempReading], kind: TempReading.Kind) -> Double? {
        let values = temps.filter { $0.kind == kind }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
