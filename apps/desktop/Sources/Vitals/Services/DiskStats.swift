import Foundation
import IOKit

/// Whole-machine disk throughput for one tick, summed over every block-storage
/// driver. 0 on the first sample.
struct DiskIOSnapshot: Sendable {
    var readPerSec: Double      // bytes/s, summed over drivers
    var writePerSec: Double
}

/// Disk throughput from `IOBlockStorageDriver` statistics (the counters `iostat`
/// reads). Sampled off the main thread by the sampler; not `@MainActor`.
///
/// Counters are kept per driver, keyed by IORegistry entry ID, so attaching or
/// ejecting a drive can't produce a fake spike in the total.
final class DiskStats {
    private var previousCounters: [UInt64: (read: UInt64, written: UInt64)] = [:]
    private var previousTimestamp: UInt64?  // CLOCK_UPTIME_RAW nanoseconds

    func sample() -> DiskIOSnapshot {
        let counters = Self.readDriverCounters()
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

        return DiskIOSnapshot(readPerSec: readPerSec, writePerSec: writePerSec)
    }

    /// `kIOBlockStorageDriverStatistics{Key,BytesReadKey,BytesWrittenKey}` from
    /// `<IOKit/storage/IOBlockStorageDriver.h>`. The storage headers aren't in
    /// IOKit's Swift module, so the ABI-stable literals are spelled out.
    private static let statisticsKey = "Statistics"
    private static let bytesReadKey = "Bytes (Read)"
    private static let bytesWrittenKey = "Bytes (Write)"

    /// Drivers without readable statistics are skipped.
    private static func readDriverCounters() -> [(id: UInt64, read: UInt64, written: UInt64)] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var counters: [(id: UInt64, read: UInt64, written: UInt64)] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
                  let statistics = IORegistryEntryCreateCFProperty(
                      service, statisticsKey as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? [String: Any]
            else { continue }

            let read = (statistics[bytesReadKey] as? NSNumber)?.uint64Value
            let written = (statistics[bytesWrittenKey] as? NSNumber)?.uint64Value
            guard let read, let written else { continue }
            counters.append((id: entryID, read: read, written: written))
        }
        return counters
    }
}
