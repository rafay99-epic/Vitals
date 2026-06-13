import Foundation

/// Memory from `/proc/meminfo`, plus pressure from `/proc/pressure/memory` (PSI).
public enum Meminfo {

    /// Parses `/proc/meminfo` into a snapshot. Each line is `Key:   <n> kB`.
    /// `used` is derived as `total − available`, the same reclaim-aware figure
    /// `free` and `htop` report (cached/buffers the kernel can drop don't count).
    public static func parse(_ content: String) -> MemorySnapshot? {
        var kb: [String: UInt64] = [:]
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmed
            // Value is "<number> kB" (or just a number for a few keys).
            if let value = parts[1].split(separator: " ").compactMap({ UInt64($0) }).first {
                kb[key] = value
            }
        }
        guard let totalKB = kb["MemTotal"] else { return nil }
        // Computed as locals (not inline in the initializer) to keep Swift's
        // expression type-checker well under its time budget.
        func bytes(_ key: String) -> UInt64 { (kb[key] ?? 0) * 1024 }
        let total: UInt64 = totalKB * 1024
        // Kernels predating MemAvailable (< 3.14) fall back to MemFree.
        let availableKB: UInt64 = kb["MemAvailable"] ?? kb["MemFree"] ?? 0
        let available: UInt64 = availableKB * 1024
        let free: UInt64 = bytes("MemFree")
        let cached: UInt64 = bytes("Cached")
        let swapTotal: UInt64 = bytes("SwapTotal")
        let swapFree: UInt64 = bytes("SwapFree")
        let swapUsed: UInt64 = swapTotal > swapFree ? swapTotal - swapFree : 0
        return MemorySnapshot(
            total: total,
            available: available,
            free: free,
            cached: cached,
            swapTotal: swapTotal,
            swapUsed: swapUsed
        )
    }

    /// Derives a coarse pressure level from PSI. PSI is the kernel's real stall
    /// signal — `some avgN` is the share of time at least one task stalled on
    /// memory, `full avgN` the share where everything stalled. The thresholds
    /// below are a documented heuristic over those real numbers, not a value
    /// invented per reading. Returns nil when PSI is unavailable (kernel < 4.20
    /// or `psi=0`), so the UI shows nothing rather than a guess.
    public static func parsePressure(_ content: String) -> MemoryPressure? {
        func avg10(_ prefix: String) -> Double? {
            for line in content.split(separator: "\n") where line.hasPrefix(prefix) {
                for token in line.split(separator: " ") where token.hasPrefix("avg10=") {
                    return Double(token.dropFirst("avg10=".count))
                }
            }
            return nil
        }
        guard let some = avg10("some") else { return nil }
        let full = avg10("full") ?? 0
        if full >= 10 { return .critical }
        if some >= 1 { return .warning }
        return .normal
    }

    public static func read(
        meminfoPath: String = "/proc/meminfo",
        pressurePath: String = "/proc/pressure/memory"
    ) -> (memory: MemorySnapshot?, pressure: MemoryPressure?) {
        let memory = (try? String(contentsOfFile: meminfoPath, encoding: .utf8)).flatMap(parse)
        let pressure = (try? String(contentsOfFile: pressurePath, encoding: .utf8)).flatMap(parsePressure)
        return (memory, pressure)
    }
}
