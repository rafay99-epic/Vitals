import Foundation
import IOKit

/// A whole-machine disk I/O reading for one tick: per-second read/write
/// throughput plus running totals, summed over every block-storage driver
/// (internal SSD and any attached external drives). Rates only exist relative
/// to a previous reading, so the first sample carries 0 rates — never a
/// fabricated spike.
struct DiskIOSnapshot: Sendable {
    var readPerSec: Double      // bytes/s, summed over drivers
    var writePerSec: Double
    var totalBytesRead: UInt64  // since boot/attach, from the drivers' counters
    var totalBytesWritten: UInt64
}

/// Live disk throughput from IOKit's `IOBlockStorageDriver` statistics — the
/// same cumulative byte counters `iostat` reads. Sampled off the main thread
/// by the sampler; **not** `@MainActor`.
///
/// Rates are deltas between consecutive `sample()` calls. Counters are kept
/// **per driver** (keyed by IORegistry entry ID, which is unique for a
/// driver's lifetime), so ejecting a drive simply drops its key and attaching
/// one starts it from a 0-rate first delta — neither event can bend the total
/// into a fake spike, mirroring `NetworkStats`' per-interface bookkeeping.
final class DiskStats {
    /// Previous per-driver byte counters plus the monotonic timestamp they
    /// were read at — the two inputs a delta needs.
    private var previousCounters: [UInt64: (read: UInt64, written: UInt64)] = [:]
    private var previousTimestamp: UInt64?  // CLOCK_UPTIME_RAW nanoseconds

    /// One reading. Rates are deltas versus the previous call; the first call
    /// reports 0 rates. Always returns a snapshot (all zeros when IOKit has
    /// no drivers to report), never nil.
    func sample() -> DiskIOSnapshot {
        let counters = Self.readDriverCounters()
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        // Elapsed since the last reading; 0 on the first call (no prior
        // stamp), which drives every rate to 0 via `CounterRate.perSecond`.
        let elapsed: TimeInterval = previousTimestamp.map { Double(now - $0) / 1_000_000_000 } ?? 0

        var readPerSec = 0.0
        var writePerSec = 0.0
        var totalRead: UInt64 = 0
        var totalWritten: UInt64 = 0
        for counter in counters {
            if let previous = previousCounters[counter.id] {
                readPerSec += CounterRate.perSecond(previous: previous.read, current: counter.read, elapsed: elapsed)
                writePerSec += CounterRate.perSecond(previous: previous.written, current: counter.written, elapsed: elapsed)
            }
            totalRead &+= counter.read
            totalWritten &+= counter.written
        }

        previousCounters = Dictionary(counters.map { ($0.id, (read: $0.read, written: $0.written)) },
                                      uniquingKeysWith: { first, _ in first })
        previousTimestamp = now

        return DiskIOSnapshot(
            readPerSec: readPerSec,
            writePerSec: writePerSec,
            totalBytesRead: totalRead,
            totalBytesWritten: totalWritten
        )
    }

    /// Property keys from `<IOKit/storage/IOBlockStorageDriver.h>` —
    /// `kIOBlockStorageDriverStatistics{Key,BytesReadKey,BytesWrittenKey}`.
    /// The storage headers aren't part of IOKit's Swift module, so the
    /// ABI-stable literals are spelled out here.
    private static let statisticsKey = "Statistics"
    private static let bytesReadKey = "Bytes (Read)"
    private static let bytesWrittenKey = "Bytes (Write)"

    /// Every block-storage driver's cumulative byte counters, from the
    /// `Statistics` property `IOBlockStorageDriver` maintains (the counters
    /// behind `iostat`). A driver with no readable statistics is skipped —
    /// skipping is honest; substituting zeros would dilute the totals.
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
