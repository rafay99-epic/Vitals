import Foundation
import IOKit
import Metal

/// A single read of the GPU's live state. Every field is optional because a
/// reading that can't be taken is reported as "unknown" — never a fabricated 0.
struct GPUSnapshot {
    /// Marketing name from Metal, e.g. "Apple M1 Pro".
    let name: String?
    /// Overall GPU busy percentage, 0...100.
    let utilization: Double?
    /// Renderer (shader/compute) busy percentage, 0...100, when exposed.
    let rendererUtilization: Double?
    /// Tiler (geometry) busy percentage, 0...100, when exposed.
    let tilerUtilization: Double?
    /// Physical GPU core count, read once from the IORegistry.
    let coreCount: Int?
    /// Bytes of (unified) system memory currently in use by the GPU.
    let memoryUsed: UInt64?
    /// Bytes the GPU driver has allocated (its working pool — always ≥ in-use).
    let memoryAllocated: UInt64?
    /// Metal's recommended working-set size — the denominator for `memoryUsed`.
    let memoryTotal: UInt64?

    init(name: String?, utilization: Double?,
         rendererUtilization: Double? = nil, tilerUtilization: Double? = nil,
         coreCount: Int? = nil,
         memoryUsed: UInt64?, memoryAllocated: UInt64? = nil, memoryTotal: UInt64?) {
        self.name = name
        self.utilization = utilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.coreCount = coreCount
        self.memoryUsed = memoryUsed
        self.memoryAllocated = memoryAllocated
        self.memoryTotal = memoryTotal
    }

    /// Fraction of the recommended working set in use, 0...1, when both are known.
    var memoryFraction: Double? {
        guard let used = memoryUsed, let total = memoryTotal, total > 0 else { return nil }
        return min(Double(used) / Double(total), 1)
    }
}

/// Reads GPU utilization and memory from the IOAccelerator registry entry — the
/// same `PerformanceStatistics` Activity Monitor reads. Needs no entitlements
/// and works on Apple Silicon. The GPU's name, total memory and core count come
/// from Metal / the IORegistry and never change during a run, so they're
/// captured once.
///
/// Lives behind the `SensorSampler` actor, so its cached state is serialized.
final class GPUSampler {
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var name = device?.name
    private lazy var memoryTotal: UInt64? = device.map { $0.recommendedMaxWorkingSetSize }
    private lazy var coreCount: Int? = Self.gpuCoreCount()

    func sample() -> GPUSnapshot? {
        let perf = Self.acceleratorPerformanceStatistics()
        let utilization = perf?["Device Utilization %"] as? Int
        let renderer = perf?["Renderer Utilization %"] as? Int
        let tiler = perf?["Tiler Utilization %"] as? Int
        let memoryUsed = perf?["In use system memory"] as? Int ?? perf?["Alloc system memory"] as? Int
        let memoryAllocated = perf?["Alloc system memory"] as? Int

        // No accelerator and no Metal device — there is no GPU to report.
        if utilization == nil && memoryUsed == nil && name == nil { return nil }

        func percent(_ value: Int?) -> Double? { value.map { min(max(Double($0), 0), 100) } }

        return GPUSnapshot(
            name: name,
            utilization: percent(utilization),
            rendererUtilization: percent(renderer),
            tilerUtilization: percent(tiler),
            coreCount: coreCount,
            memoryUsed: memoryUsed.map(UInt64.init),
            memoryAllocated: memoryAllocated.map(UInt64.init),
            memoryTotal: memoryTotal
        )
    }

    /// The `PerformanceStatistics` dictionary of the first IOAccelerator that
    /// exposes one. On Apple Silicon there is a single integrated GPU.
    private static func acceleratorPerformanceStatistics() -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let perf = props["PerformanceStatistics"] as? [String: Any] {
                return perf
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Physical GPU core count, published on the GPU's device-tree node as
    /// `gpu-core-count`. Searched recursively through the accelerator's parents
    /// since the property doesn't sit on the IOAccelerator entry itself. Read
    /// once — it can't change.
    private static func gpuCoreCount() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let value = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "gpu-core-count" as CFString,
                kCFAllocatorDefault, options) as? Int, value > 0 {
                return value
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }
}
