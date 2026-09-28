import Foundation

/// One AI coding tool found on this machine. Auth, config and user settings
/// under the tool's directory are never touched.
struct AITool {
    let name: String
}

/// Caches, temp files, logs and superseded versions left behind by AI coding
/// tools. Lists only paths that exist, only for installed tools. Pass
/// `home`/`tmpRoot`/`now` to test against a fixture.
enum AIToolJunk {
    /// A tmp working directory younger than this may back a live session, so it
    /// is left alone even when a tool is detected.
    static let tempAgeHours = 24

    /// The AI tools detected under `home` (detect directory present).
    static func detectedTools(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [AITool] {
        Tool.allCases.compactMap { tool in
            let dir = tool.detectDir(home: home)
            guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
            return AITool(name: tool.displayName)
        }
    }

    /// Every detected tool's regenerable junk (caches, temp, logs, stale
    /// versions). Empty when no AI tool is installed.
    static func cacheItems(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        tmpRoot: URL = URL(fileURLWithPath: "/private/tmp"),
        now: Date = Date()
    ) -> [URL] {
        Tool.allCases
            .filter { FileManager.default.fileExists(atPath: $0.detectDir(home: home).path) }
            .flatMap { $0.cacheItems(home: home, tmpRoot: tmpRoot, now: now) }
    }

    // MARK: Tool table

    private enum Tool: CaseIterable {
        case claudeCode, claudeDesktop, chatGPT, cursor, codex, copilot, gemini

        var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .claudeDesktop: return "Claude"
            case .chatGPT: return "ChatGPT"
            case .cursor: return "Cursor"
            case .codex: return "Codex"
            case .copilot: return "Copilot"
            case .gemini: return "Gemini CLI"
            }
        }

        /// The tool is present iff this directory exists.
        func detectDir(home: URL) -> URL {
            switch self {
            case .claudeCode: return home.appendingPathComponent(".claude")
            case .claudeDesktop: return home.appendingPathComponent("Library/Application Support/Claude")
            case .chatGPT: return home.appendingPathComponent("Library/Application Support/com.openai.chat")
            case .cursor: return home.appendingPathComponent("Library/Application Support/Cursor")
            case .codex: return home.appendingPathComponent(".codex")
            case .copilot: return home.appendingPathComponent(".copilot")
            case .gemini: return home.appendingPathComponent(".gemini")
            }
        }

        func cacheItems(home: URL, tmpRoot: URL, now: Date) -> [URL] {
            let caches = home.appendingPathComponent("Library/Caches")
            let localShare = home.appendingPathComponent(".local/share")

            switch self {
            case .claudeCode:
                var items: [URL] = []
                // Stale tmp dirs only: a live session runs from a fresh one.
                let tmpBase = tmpRoot.appendingPathComponent("claude-\(getuid())")
                items += staleContents(of: tmpBase, olderThanHours: AIToolJunk.tempAgeHours, now: now)
                // Only aged shell-snapshots: a running session sources a fresh one
                // on every Bash call, so deleting the directory breaks it.
                // `file-history` is deliberately absent: it's the per-edit undo
                // store (recovery data, not cache).
                items += staleContents(of: home.appendingPathComponent(".claude/shell-snapshots"),
                                       olderThanHours: AIToolJunk.tempAgeHours, now: now)
                items += existing([
                    home.appendingPathComponent(".claude/telemetry"),
                    home.appendingPathComponent(".claude/statsig"),
                    caches.appendingPathComponent("claude-cli-nodejs"),
                ])
                items += oldVersions(
                    in: localShare.appendingPathComponent("claude/versions"),
                    pointers: versionPointers(home: home, shareSubdir: "claude")
                )
                return items

            case .claudeDesktop:
                return electronCaches(in: detectDir(home: home))
                    + existing([caches.appendingPathComponent("com.anthropic.claudefordesktop")])

            case .chatGPT:
                return existing([caches.appendingPathComponent("com.openai.chat")])
                    + electronCaches(in: detectDir(home: home))

            case .cursor:
                return electronCaches(in: detectDir(home: home), extra: ["CachedData", "CachedExtensionVSIXs"])
                    + existing([caches.appendingPathComponent("com.todesktop.230313mzl4w4u92")])
                    + oldVersions(
                        in: localShare.appendingPathComponent("cursor-agent/versions"),
                        pointers: versionPointers(home: home, shareSubdir: "cursor-agent")
                    )

            case .codex:
                return existing([
                    home.appendingPathComponent(".codex/log"),
                    home.appendingPathComponent(".cache/codex-runtimes"),
                ])

            case .copilot:
                return existing([caches.appendingPathComponent("copilot")])
                    + oldVersions(in: home.appendingPathComponent(".copilot/pkg"), pointers: [])

            case .gemini:
                return existing([home.appendingPathComponent(".gemini/tmp")])
            }
        }

        /// Symlinks that name the *active* version (never listed): any symlink in
        /// `~/.local/bin`, plus sibling `latest`/`current` pointers next to the
        /// versions directory.
        private func versionPointers(home: URL, shareSubdir: String) -> [URL] {
            let bin = home.appendingPathComponent(".local/bin")
            let binLinks = (try? FileManager.default.contentsOfDirectory(
                at: bin, includingPropertiesForKeys: nil)) ?? []
            let shareDir = home.appendingPathComponent(".local/share/\(shareSubdir)")
            return binLinks + [shareDir.appendingPathComponent("latest"),
                               shareDir.appendingPathComponent("current")]
        }
    }
}

// MARK: - File helpers

/// Regenerable cache subfolders inside an Electron app's data directory — never
/// its `Local Storage`, `IndexedDB`, cookies or user settings.
private let electronCacheDirNames = [
    "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
    "Service Worker/CacheStorage",
]

private func existing(_ urls: [URL]) -> [URL] {
    urls.filter { FileManager.default.fileExists(atPath: $0.path) }
}

private func electronCaches(in base: URL, extra: [String] = []) -> [URL] {
    existing((electronCacheDirNames + extra).map { base.appendingPathComponent($0) })
}

/// Immediate contents of `dir` whose mtime is older than `hours`, so a running
/// session's fresh entry is spared.
private func staleContents(of dir: URL, olderThanHours hours: Int, now: Date) -> [URL] {
    let fm = FileManager.default
    let cutoff = now.addingTimeInterval(-Double(hours) * 3600)
    let keys: Set<URLResourceKey> = [.contentModificationDateKey]
    guard let entries = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: Array(keys), options: []) else { return [] }
    return entries.filter { url in
        guard let modified = try? url.resourceValues(forKeys: keys).contentModificationDate
        else { return false }
        return modified < cutoff
    }
}

/// Superseded version directories under a tool's `versions` dir: keeps the
/// newest remaining version, keeps every version an active-version symlink
/// points at (and never lists a symlink itself), lists the rest.
private func oldVersions(in versionsDir: URL, pointers: [URL]) -> [URL] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: versionsDir.path) else { return [] }

    // Resolve pointers to the versions they protect — never a symlink target.
    var protected: Set<String> = []
    for link in pointers {
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: link.path) else { continue }
        let target = URL(fileURLWithPath: dest, relativeTo: link.deletingLastPathComponent())
        protected.insert(target.standardizedFileURL.path)
    }

    let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .contentModificationDateKey]
    let entries = (try? fm.contentsOfDirectory(
        at: versionsDir, includingPropertiesForKeys: Array(keys), options: [])) ?? []
    var candidates: [(url: URL, modified: Date)] = []
    for entry in entries {
        guard let v = try? entry.resourceValues(forKeys: keys) else { continue }
        if v.isSymbolicLink == true { continue }                            // never a symlink
        if protected.contains(entry.standardizedFileURL.path) { continue }  // active version
        // Versions can be plain files (Claude Code), so require a version-shaped
        // name instead: a stray manifest.json or .DS_Store must never count as
        // the newest version and shield a real one.
        if !isVersionShaped(entry.lastPathComponent) { continue }
        candidates.append((entry, v.contentModificationDate ?? .distantPast))
    }
    guard candidates.count > 1 else { return [] }                           // keep the only/newest
    return candidates.sorted { $0.modified > $1.modified }.dropFirst().map(\.url)
}

/// True for names like `2.0.14` or `v2.0.14`: an optional `v` then a digit.
private func isVersionShaped(_ name: String) -> Bool {
    var rest = Substring(name)
    if rest.first == "v" { rest = rest.dropFirst() }
    return rest.first?.isNumber == true
}

