import Foundation
import PrivateSensors

/// Live power draw of the SoC's main rails, in watts. Every figure is a real
/// IOReport energy delta divided by elapsed time — never an assumed maximum or
/// a derived percentage. The Neural Engine in particular reads near-zero at idle
/// and only climbs under Core ML / vision work, which is exactly the honest
/// signal: it says so when nothing is using it.
struct PowerSnapshot {
    let cpuWatts: Double
    let gpuWatts: Double
    let aneWatts: Double

    var total: Double { cpuWatts + gpuWatts + aneWatts }
}

/// Samples the SoC power rails through the IOReport C shim. Holds the IOReport
/// subscription for its lifetime (creating one per tick is the costly part) and
/// reports `nil` whenever a reading isn't available — IOReport missing, or the
/// very first sample, which has no prior counter to diff against.
///
/// Lives behind the `SensorSampler` actor, so the underlying handle is only ever
/// touched from one executor.
final class SoCPowerSampler {
    private let handle: UnsafeMutableRawPointer?

    init() {
        handle = vitals_socpower_create()
    }

    deinit {
        vitals_socpower_destroy(handle)
    }

    func sample() -> PowerSnapshot? {
        guard let handle else { return nil }
        var out = VitalsSoCPower()
        guard vitals_socpower_sample(handle, &out) != 0 else { return nil }
        return PowerSnapshot(cpuWatts: out.cpu_watts, gpuWatts: out.gpu_watts, aneWatts: out.ane_watts)
    }
}
