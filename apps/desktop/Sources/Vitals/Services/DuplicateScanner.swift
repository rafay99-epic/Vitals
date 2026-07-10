import Foundation
import CryptoKit

/// Finds sets of byte-for-byte identical files under the user's content folders,
/// so the redundant copies can be reclaimed. Like every Service it is UI-free.
///
/// **Honesty over decoration.** Two files are only ever reported as duplicates
/// when their *full contents* hash identically — never on a size or name
/// coincidence. Candidates are narrowed cheaply first (grouped by size, then by a
/// 64 KB head hash) before a streamed full SHA-256 confirms them, so a scan stays
/// fast without ever guessing that two files are "the same".
///
/// **Trash-only contract.** These are the user's own files, so removal is always
/// recoverable: `trash(_:)` moves copies to the Trash via `FileManager.trashItem`
/// and nothing here ever deletes permanently — the same contract as
/// `LargeFileScanner`. The safe walk (symlinks, hidden files, packages, the app's
/// own data, depth bound) is shared via `FileWalk`, so the two finders can't drift.
enum DuplicateScanner {
    /// One file that participates in a duplicate set. `sizeBytes` is the allocated
    /// on-disk size (what trashing this copy actually reclaims). `contentHash` is
    /// its full SHA-256 at scan time — re-checked immediately before trashing, so
    /// a file that changed since the scan is never removed as a stale "duplicate".
    struct File: Identifiable, Hashable {
        let url: URL
        let name: String
        let sizeBytes: UInt64
        let modified: Date?
        let contentHash: String

        var id: URL { url }
    }

    /// A set of ≥2 byte-for-byte identical files. `files` is ordered oldest-first,
    /// so `keeper` (the oldest) is the copy kept by default and `redundant` is the
    /// rest. `id` is the content hash — stable across rescans. `sizeBytes` is the
    /// files' shared logical size (for the "N copies · X each" label).
    struct Group: Identifiable, Hashable {
        let id: String
        let sizeBytes: UInt64
        let files: [File]

        var count: Int { files.count }
        /// Bytes reclaimable by keeping exactly one copy — the sum of the redundant
        /// copies' *allocated* sizes (not size × count, since sparse copies of the
        /// same content can occupy different amounts on disk).
        var wastedBytes: UInt64 { redundant.reduce(0) { $0 + $1.sizeBytes } }
        /// The copy kept by default (the oldest); never suggested for removal.
        var keeper: File? { files.first }
        /// The copies safe to trash while still keeping one.
        var redundant: [File] { Array(files.dropFirst()) }
    }

    /// Outcome of a trash pass: bytes freed (credited only once the original path
    /// is confirmed gone) plus any items that couldn't be trashed, with a reason.
    struct TrashResult {
        var freedBytes: UInt64
        var failures: [(url: URL, reason: String)]
    }

    /// The user's content folders — the same roots the Large & Old Files review
    /// walks, via the shared `FileWalk`.
    static func defaultRoots(home: URL) -> [URL] { FileWalk.defaultContentRoots(home: home) }

    // MARK: Scanning

    /// Walks `roots`, groups files whose contents are identical, and returns the
    /// sets of ≥2 copies ranked by reclaimable bytes (descending), capped at
    /// `limit`. Only regular files at or above `minSizeBytes` are considered —
    /// packages are never hashed, and files below the floor rarely matter for
    /// space and would only slow the scan.
    static func scan(roots: [URL], minSizeBytes: UInt64, limit: Int = 200) -> [Group] {
        // 1. Collect qualifying regular files, bucketed by **logical** size. Two
        //    copies of the same content always share a logical size (even if one is
        //    sparse and occupies less on disk), so this is the correct free first
        //    discriminator; allocated size is kept for reclaim reporting.
        var bySize: [UInt64: [Candidate]] = [:]
        FileWalk.enumerate(roots: roots) { entry in
            if Task.isCancelled { return false }
            guard !entry.isPackage, entry.logicalSize >= minSizeBytes else { return true }
            bySize[entry.logicalSize, default: []].append(
                Candidate(url: entry.url, name: entry.url.lastPathComponent,
                          allocatedBytes: entry.regularFileSize, modified: entry.modified))
            return true
        }

        var groups: [Group] = []
        for (logicalSize, sameSize) in bySize where sameSize.count >= 2 {
            if Task.isCancelled { break }
            // 2. Narrow by a cheap head hash before paying for the full hash.
            for headBucket in bucketed(sameSize, by: { headHash(of: $0.url) }) where headBucket.count >= 2 {
                if Task.isCancelled { break }
                // 3. Confirm true duplicates with the full-content hash, and stamp
                //    it onto each file so trashing can revalidate later.
                for (hash, identical) in keyed(headBucket, by: { fullHash(of: $0.url) }) where identical.count >= 2 {
                    let files = identical
                        .sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
                        .map { File(url: $0.url, name: $0.name, sizeBytes: $0.allocatedBytes,
                                    modified: $0.modified, contentHash: hash) }
                    groups.append(Group(id: hash, sizeBytes: logicalSize, files: files))
                }
            }
        }

        // 4. Most reclaimable first, capped.
        let sorted = groups.sorted { $0.wastedBytes > $1.wastedBytes }
        return limit < sorted.count ? Array(sorted.prefix(limit)) : sorted
    }

    /// A file in the pre-hash phase — identity plus the sizes we already know,
    /// before the content hash that turns it into a `File`.
    private struct Candidate {
        let url: URL
        let name: String
        let allocatedBytes: UInt64
        let modified: Date?
    }

    /// Buckets candidates by a hash key, dropping any whose key can't be computed
    /// (an unreadable file is never lumped in with others). Order within a bucket
    /// follows input order.
    private static func keyed(_ files: [Candidate], by key: (Candidate) -> String?) -> [String: [Candidate]] {
        var out: [String: [Candidate]] = [:]
        for file in files {
            if Task.isCancelled { break }
            guard let k = key(file) else { continue }
            out[k, default: []].append(file)
        }
        return out
    }
    private static func bucketed(_ files: [Candidate], by key: (Candidate) -> String?) -> [[Candidate]] {
        Array(keyed(files, by: key).values)
    }

    // MARK: Hashing

    /// SHA-256 of the first `bytes` of the file — a cheap discriminator to avoid
    /// full-hashing files that only happen to share a size. `nil` if unreadable.
    static func headHash(of url: URL, bytes: Int = 65_536) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = (try? handle.read(upToCount: bytes)) ?? nil else { return nil }
        return hex(SHA256.hash(data: data))
    }

    /// SHA-256 of the whole file, streamed in chunks so a large file never loads
    /// into memory at once. `nil` if unreadable or cancelled mid-read.
    static func fullHash(of url: URL, chunkSize: Int = 1 << 20) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            let chunk: Data
            do { chunk = try handle.read(upToCount: chunkSize) ?? Data() } catch { return nil }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Trashing

    /// Moves each file to the Trash — the only deletion this type performs, and a
    /// recoverable one. Before trashing, each file's current content is re-hashed
    /// and compared to the hash captured at scan time: a file that changed or was
    /// replaced since the scan is **not** a duplicate any more, so it's left in
    /// place and recorded as a failure rather than trashed on stale information.
    /// After trashing we confirm the original path is gone before crediting its
    /// bytes; anything that fails is recorded with a reason, never force-deleted.
    static func trash(_ files: [File]) -> TrashResult {
        let fm = FileManager.default
        var result = TrashResult(freedBytes: 0, failures: [])
        for file in files {
            // Time-of-check/time-of-use guard: only remove what still matches the
            // content we identified as a duplicate.
            guard fullHash(of: file.url) == file.contentHash else {
                result.failures.append((url: file.url, reason: "changed since scan"))
                continue
            }
            do {
                try fm.trashItem(at: file.url, resultingItemURL: nil)
                if fm.fileExists(atPath: file.url.path) {
                    result.failures.append((url: file.url, reason: "still present after trashing"))
                } else {
                    result.freedBytes += file.sizeBytes
                }
            } catch {
                Log.notice(.cleanup, "couldn't trash \(file.name)", error: error)
                result.failures.append((url: file.url, reason: error.localizedDescription))
            }
        }
        return result
    }
}
