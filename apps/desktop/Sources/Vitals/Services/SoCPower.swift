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
        let snapshot = PowerSnapshot(cpuWatts: out.cpu_watts, gpuWatts: out.gpu_watts, aneWatts: out.ane_watts)
        // A running SoC never spends exactly 0 J between samples. An all-zero delta
        // means IOReport's energy counters have stalled (seen on macOS 27), so
        // report no reading rather than a fabricated 0 W.
        guard snapshot.total > 0 else {
            Log.noticeOnce(.sensors, key: "socpower-stalled", "IOReport energy counters aren't advancing; power readings unavailable")
            return nil
        }
        return snapshot
    }
}
