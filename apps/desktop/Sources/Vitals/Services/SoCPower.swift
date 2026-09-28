import Foundation
import PrivateSensors

/// SoC rail power in watts: IOReport energy deltas over elapsed time. The Neural
/// Engine reads near zero unless Core ML or vision work is running.
struct PowerSnapshot {
    let cpuWatts: Double
    let gpuWatts: Double
    let aneWatts: Double

    var total: Double { cpuWatts + gpuWatts + aneWatts }
}

/// SoC rail power through the IOReport C shim. Holds one subscription for its
/// lifetime, since creating one is the costly part. Nil when IOReport is missing
/// or on the first sample (nothing to diff against).
///
/// Lives behind the `SensorSampler` actor, so the handle is used from one executor.
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
