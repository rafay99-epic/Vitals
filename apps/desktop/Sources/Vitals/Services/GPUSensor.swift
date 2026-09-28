import Foundation
import IOKit
import Metal

/// One read of the GPU. A field that can't be read is nil.
struct GPUSnapshot {
    /// Marketing name from Metal, e.g. "Apple M1 Pro".
    let name: String?
    /// Busy percentage, 0...100.
    let utilization: Double?
    /// Renderer (shader/compute) busy percentage, when exposed.
    let rendererUtilization: Double?
    /// Tiler (geometry) busy percentage, when exposed.
    let tilerUtilization: Double?
    let coreCount: Int?
    /// Unified memory in use by the GPU, in bytes.
    let memoryUsed: UInt64?
    /// The driver's allocated pool, always ≥ in-use.
    let memoryAllocated: UInt64?
    /// Metal's recommended working-set size, the denominator for `memoryUsed`.
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

/// GPU utilization and memory from the IOAccelerator's `PerformanceStatistics`
/// (what Activity Monitor reads; no entitlements needed). Name, total memory and
/// core count are captured once.
///
/// Lives behind the `SensorSampler` actor, so its cached state is serialized.
final class GPUSampler {
    /// Read once. The Metal device itself isn't kept alive.
    private lazy var device: (name: String?, memoryTotal: UInt64?) = {
        guard let device = MTLCreateSystemDefaultDevice() else { return (nil, nil) }
        return (device.name, device.recommendedMaxWorkingSetSize)
    }()
    private lazy var coreCount: Int? = Self.gpuCoreCount()
    /// Looked up once and retained; released in `deinit`.
    private lazy var accelerator: io_service_t = Self.findAccelerator()

    deinit {
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }

    func sample() -> GPUSnapshot? {
        let name = device.name
        // One key, not a copy of the entry's whole property table.
        let perf = accelerator == 0 ? nil : IORegistryEntryCreateCFProperty(
            accelerator, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any]
        let utilization = perf?["Device Utilization %"] as? Int
        let renderer = perf?["Renderer Utilization %"] as? Int
        let tiler = perf?["Tiler Utilization %"] as? Int
        let memoryUsed = perf?["In use system memory"] as? Int ?? perf?["Alloc system memory"] as? Int
        let memoryAllocated = perf?["Alloc system memory"] as? Int

        // No accelerator and no Metal device.
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

    /// The first IOAccelerator exposing `PerformanceStatistics`, retained (+1).
    /// 0 when there's none (a VM).
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

    /// `gpu-core-count` lives on the GPU's device-tree node, not the
    /// IOAccelerator entry, so search the accelerator's parents.
    private static func gpuCoreCount() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        while case let service = IOIteratorNext(iterator), service != 0 {
            // A fresh `let` per pass, so the defer releases this entry, not the next.
            defer { IOObjectRelease(service) }
            if let value = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "gpu-core-count" as CFString,
                kCFAllocatorDefault, options) as? Int, value > 0 {
                return value
            }
        }
        return nil
    }
}
