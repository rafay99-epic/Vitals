import Foundation
import IOKit

/// Whole-machine disk throughput for one tick, summed over every block-storage
/// driver. 0 on the first sample.
struct DiskIOSnapshot: Equatable, Sendable {
    var readPerSec: Double      // bytes/s, summed over drivers
    var writePerSec: Double
    var space: VolumeSpace?
}

struct VolumeSpace: Equatable, Sendable {
    let name: String?
    let freeBytes: Int64
    let totalBytes: Int64

    static func boot() -> VolumeSpace? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage, free >= 0 else { return nil }
        return VolumeSpace(name: values.volumeName, freeBytes: free, totalBytes: Int64(total))
    }
}

/// Disk throughput from `IOBlockStorageDriver` statistics (the counters `iostat`
/// reads). Sampled off the main thread by the sampler; not `@MainActor`.
///
/// Counters are kept per driver, keyed by IORegistry entry ID, so attaching or
/// ejecting a drive can't produce a fake spike in the total.
final class DiskStats {
    private var previousCounters: [UInt64: (read: UInt64, written: UInt64)] = [:]
    private var previousTimestamp: UInt64?  // CLOCK_UPTIME_RAW nanoseconds

    /// Matching every driver each tick walks the IORegistry, so the list is kept
    /// and re-matched every minute, or as soon as a listed driver stops
    /// answering, to pick up attached and ejected drives.
    private var drivers: [(id: UInt64, service: io_object_t)] = []
    private var listedAt = Date.distantPast
    private static let relistInterval: TimeInterval = 60
    private var space: VolumeSpace?
    private var spaceAt = Date.distantPast
    private static let spaceInterval: TimeInterval = 30

    deinit { drivers.forEach { IOObjectRelease($0.service) } }

    func sample() -> DiskIOSnapshot {
        if drivers.isEmpty || Date().timeIntervalSince(listedAt) >= Self.relistInterval { relist() }
        var counters = readCounters()
        if counters.count < drivers.count {
            relist()
            counters = readCounters()
        }
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        // 0 on the first call, which makes every rate 0.
        let elapsed: TimeInterval = previousTimestamp.map { Double(now - $0) / 1_000_000_000 } ?? 0

        var readPerSec = 0.0
        var writePerSec = 0.0
        for counter in counters {
            if let previous = previousCounters[counter.id] {
                readPerSec += CounterRate.perSecond(previous: previous.read, current: counter.read, elapsed: elapsed)
                writePerSec += CounterRate.perSecond(previous: previous.written, current: counter.written, elapsed: elapsed)
            }
        }

        previousCounters = Dictionary(counters.map { ($0.id, (read: $0.read, written: $0.written)) },
                                      uniquingKeysWith: { first, _ in first })
        previousTimestamp = now

        if Date().timeIntervalSince(spaceAt) >= Self.spaceInterval {
            space = VolumeSpace.boot()
            spaceAt = Date()
        }
        return DiskIOSnapshot(readPerSec: readPerSec, writePerSec: writePerSec, space: space)
    }

    /// `kIOBlockStorageDriverStatistics{Key,BytesReadKey,BytesWrittenKey}` from
    /// `<IOKit/storage/IOBlockStorageDriver.h>`. The storage headers aren't in
    /// IOKit's Swift module, so the ABI-stable literals are spelled out.
    private static let statisticsKey = "Statistics"
    private static let bytesReadKey = "Bytes (Read)"
    private static let bytesWrittenKey = "Bytes (Write)"

    private func relist() {
        drivers.forEach { IOObjectRelease($0.service) }
        drivers = []
        listedAt = Date()
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
                  Self.counters(of: service) != nil
            else {
                IOObjectRelease(service)
                continue
            }
            drivers.append((id: entryID, service: service))
        }
    }

    /// Only drivers with readable statistics are listed, so a shorter result
    /// means a drive went away.
    private func readCounters() -> [(id: UInt64, read: UInt64, written: UInt64)] {
        drivers.compactMap { driver in
            Self.counters(of: driver.service).map { (id: driver.id, read: $0.read, written: $0.written) }
        }
    }

    private static func counters(of service: io_object_t) -> (read: UInt64, written: UInt64)? {
        guard let statistics = IORegistryEntryCreateCFProperty(
            service, statisticsKey as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any],
            let read = (statistics[bytesReadKey] as? NSNumber)?.uint64Value,
            let written = (statistics[bytesWrittenKey] as? NSNumber)?.uint64Value
        else { return nil }
        return (read, written)
    }
}
