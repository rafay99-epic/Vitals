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
}

/// Reads GPU utilization and memory from the IOAccelerator registry entry — the
/// same `PerformanceStatistics` Activity Monitor reads. Needs no entitlements
/// and works on Apple Silicon. The GPU's name, total memory and core count come
/// from Metal / the IORegistry and never change during a run, so they're
/// captured once.
///
/// Lives behind the `SensorSampler` actor, so its cached state is serialized.
final class GPUSampler {
    /// Name and recommended working set, read once. The Metal device isn't kept:
    /// a menu-bar app has no reason to hold a GPU device for its whole life.
    private lazy var device: (name: String?, memoryTotal: UInt64?) = {
        guard let device = MTLCreateSystemDefaultDevice() else { return (nil, nil) }
        return (device.name, device.recommendedMaxWorkingSetSize)
    }()
    private lazy var coreCount: Int? = Self.gpuCoreCount()
    /// The IOAccelerator that publishes statistics, looked up once and retained.
    private lazy var accelerator: io_service_t = Self.findAccelerator()

    deinit {
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }

    func sample() -> GPUSnapshot? {
        let name = device.name
        // Just the one key, not a copy of the entry's whole property table.
        let perf = accelerator == 0 ? nil : IORegistryEntryCreateCFProperty(
            accelerator, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any]
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
            memoryTotal: device.memoryTotal
        )
    }

    /// The first IOAccelerator exposing `PerformanceStatistics`, retained (+1);
    /// 0 when there's none (a VM). On Apple Silicon there's one integrated GPU.
    private static func findAccelerator() -> io_service_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0) {
                stats.release()   // Create (+1): only probing for presence
                return service
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return 0
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
