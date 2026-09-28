import Foundation

/// Finds regenerable developer build artifacts (`node_modules`, `target`,
/// `.next`, `Pods`, `DerivedData`, ...) under the user's code folders.
///
/// Safety-critical: `delete` removes directories **permanently** (they're
/// regenerable, so the Trash would only waste space). The walk never follows
/// symlinks, never descends into a found artifact, and skips hidden dirs except
/// `hiddenArtifactNames`. An artifact counts only under a project marker, with
/// its name allowlisted and context gate satisfied (`target` needs a sibling
/// `Cargo.toml`, `Pods` a `Podfile`, `dist`/`build`/`out` a marker in the
/// parent), or with a valid `CACHEDIR.TAG`. `isDeletableArtifact` re-validates
/// every path before removal; the test suite locks it.
enum DevJunkScanner {
    struct Artifact: Identifiable, Hashable {
        let url: URL
        let kindName: String
        var sizeBytes: UInt64
        let modified: Date?
        var id: URL { url }
    }

    struct Project: Identifiable {
        let root: URL
        let name: String
        let lastActive: Date?
        var artifacts: [Artifact]
        var id: URL { root }
        var totalBytes: UInt64 { artifacts.reduce(0) { $0 + $1.sizeBytes } }
    }

    struct DeleteResult {
        var freedBytes: UInt64
        var failures: [(url: URL, reason: String)]
    }

    // MARK: Vocabulary

    /// The deepest a directory may sit below a scan root before the walk stops.
    static let maxDepth = 6

    /// Files whose presence marks a directory as a project. An artifact is only
    /// attributed to the nearest ancestor carrying one of these.
    static let projectIndicators = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "requirements.txt",
        "Podfile", "build.gradle", "settings.gradle", "build.gradle.kts",
        "settings.gradle.kts", "Package.swift", ".git",
    ]

    /// Exact directory names treated as build/dependency artifacts. Gated names
    /// are checked in `candidateArtifactURL` / `isNameAllowlisted`.
    static let artifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", "dist", "build", "out", "target",
        ".venv", "venv", "Pods", "Carthage", ".gradle", ".turbo",
        ".parcel-cache", "DerivedData",
    ]

    /// The subset of `artifactNames` accepted with no context gate, shared by
    /// `candidateArtifactURL` and `isNameAllowlisted` so they can't drift.
    private static let ungatedArtifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".venv", "venv",
        ".turbo", ".parcel-cache", ".gradle", "DerivedData",
    ]

    /// Hidden names that are still artifact candidates. The walk skips every
    /// other dot-directory.
    static let hiddenArtifactNames: Set<String> = [
        ".next", ".nuxt", ".venv", ".turbo", ".parcel-cache", ".gradle",
    ]

    /// Cache Directory Tagging spec signature. A dir whose `CACHEDIR.TAG` starts
    /// with it is a cache and safe to clear.
    private static let cacheDirSignature = "Signature: 8a477f597d28d172789f06886806bc55"

    // MARK: Roots

    /// The existing, non-symlink subset of the usual code homes. Symlinks are
    /// skipped so the walk can never be redirected out of the home folder.
    static func defaultRoots(home: URL) -> [URL] {
        let names = ["Code", "Developer", "Projects", "dev", "work", "Documents", "Desktop"]
        return names.compactMap { name in
            let url = home.appendingPathComponent(name, isDirectory: true)
            guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  vals.isDirectory == true, vals.isSymbolicLink != true else { return nil }
            return url
        }
    }

    // MARK: Scanning

    /// Walks every root and returns the projects that own at least one artifact.
    /// Structure only — artifact sizes are 0 until `measured` fills them.
    static func scan(roots: [URL]) -> [Project] {
        let fm = FileManager.default
        var collected: [(project: URL, artifact: Artifact)] = []
        var order: [URL] = []
        var seenProject = Set<URL>()

        func noteOrder(_ project: URL) {
            if seenProject.insert(project).inserted { order.append(project) }
        }

        func walk(_ dir: URL, depth: Int, inheritedProject: URL?) {
            if Task.isCancelled { return }
            if isVitalsPath(dir) { return }
            let project = hasProjectIndicator(dir) ? dir : inheritedProject

            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: Array(keys), options: []) else { return }

            for child in entries {
                let vals = try? child.resourceValues(forKeys: keys)
                if vals?.isSymbolicLink == true { continue }          // never follow symlinks
                guard vals?.isDirectory == true else { continue }
                let name = child.lastPathComponent
                if name.hasPrefix(".") && !hiddenArtifactNames.contains(name) { continue }
                if isVitalsPath(child) { continue }
                let childDepth = depth + 1
                if childDepth > maxDepth { continue }

                if let artifactURL = candidateArtifactURL(child: child, parentDir: dir) {
                    record(project, artifactURL, into: &collected, noteOrder: noteOrder)
                    continue                                          // never descend into an artifact
                }
                if hasValidCacheDirTag(child) {
                    record(project, child, into: &collected, noteOrder: noteOrder)
                    continue
                }
                walk(child, depth: childDepth, inheritedProject: project)
            }
        }

        for root in roots {
            guard let vals = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  vals.isDirectory == true, vals.isSymbolicLink != true else { continue }
            walk(root.standardizedFileURL, depth: 0, inheritedProject: nil)
        }

        let survivors = dropNested(collected)

        var byProject: [URL: [Artifact]] = [:]
        for item in survivors { byProject[item.project, default: []].append(item.artifact) }

        var projects: [Project] = []
        for root in order {
            guard let artifacts = byProject[root], !artifacts.isEmpty else { continue }
            projects.append(Project(
                root: root, name: root.lastPathComponent,
                lastActive: lastActive(root: root, artifacts: artifacts),
                artifacts: artifacts))
        }
        return projects
    }

    private static func record(
        _ project: URL?, _ url: URL,
        into collected: inout [(project: URL, artifact: Artifact)],
        noteOrder: (URL) -> Void
    ) {
        // No project ancestor: no artifact (the caller still skips descending).
        guard let project else { return }
        let key = project.standardizedFileURL
        let std = url.standardizedFileURL
        let modified = try? std.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        noteOrder(key)
        collected.append((key, Artifact(url: std, kindName: std.lastPathComponent,
                                        sizeBytes: 0, modified: modified ?? nil)))
    }

    /// The URL to attribute for a candidate child, or nil if it isn't an
    /// artifact. Carthage resolves to its `Build` subdirectory only.
    private static func candidateArtifactURL(child: URL, parentDir: URL) -> URL? {
        let fm = FileManager.default
        let name = child.lastPathComponent
        switch name {
        case let name where Self.ungatedArtifactNames.contains(name):
            return child
        case "target":
            return fm.fileExists(atPath: parentDir.appendingPathComponent("Cargo.toml").path) ? child : nil
        case "Pods":
            return fm.fileExists(atPath: parentDir.appendingPathComponent("Podfile").path) ? child : nil
        case "dist", "build", "out":
            return hasProjectIndicator(parentDir) ? child : nil
        case "Carthage":
            let build = child.appendingPathComponent("Build")
            let vals = try? build.resourceValues(forKeys: [.isDirectoryKey])
            return vals?.isDirectory == true ? build : nil
        default:
            return nil
        }
    }

    /// Drops any collected artifact that lives inside another collected one.
    /// Sorting by path puts an ancestor before its descendants, so a single
    /// forward pass is enough; exact duplicates fall out here too.
    private static func dropNested(
        _ items: [(project: URL, artifact: Artifact)]
    ) -> [(project: URL, artifact: Artifact)] {
        let sorted = items.sorted { $0.artifact.url.path < $1.artifact.url.path }
        var kept: [(project: URL, artifact: Artifact)] = []
        var keptPaths: [String] = []
        for item in sorted {
            let path = item.artifact.url.path
            if keptPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
            kept.append(item)
            keptPaths.append(path)
        }
        return kept
    }

    /// Newest mtime among the root's immediate children, ignoring artifacts so an
    /// `npm install` doesn't make a dormant project look active.
    private static func lastActive(root: URL, artifacts: [Artifact]) -> Date? {
        let fm = FileManager.default
        let artifactPaths = Set(artifacts.map { $0.url.path })
        guard let children = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return nil }
        var newest: Date?
        for child in children where !artifactPaths.contains(child.standardizedFileURL.path) {
            guard let date = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            if newest == nil || date > newest! { newest = date }
        }
        return newest
    }

    // MARK: Measuring

    /// Fills each artifact's `sizeBytes`.
    static func measured(_ project: Project) -> Project {
        var project = project
        project.artifacts = project.artifacts.map { artifact in
            var artifact = artifact
            artifact.sizeBytes = AppInventory.directorySize(artifact.url)
            return artifact
        }
        return project
    }

    // MARK: Deletion

    /// The test-locked validator, independent of how the path was found. Every
    /// clause must hold before an artifact may be removed.
    static func isDeletableArtifact(_ url: URL, roots: [URL]) -> Bool {
        // Reject traversal on the raw input: standardization would collapse it.
        guard !url.pathComponents.contains("..") else { return false }

        let std = url.standardizedFileURL
        let path = std.path
        // /System is checked on the *unresolved* path on purpose: resolving
        // crosses the firmlink to /System/Volumes/Data and would reject every ~/ path.
        guard !path.hasPrefix("/System") else { return false }
        guard !isVitalsPath(std) else { return false }
        guard roots.contains(where: { atLeastTwoBelow(path, root: $0) }) else { return false }

        // The resolved path must also sit two below a resolved root, so a symlinked
        // intermediate dir can't redirect removeItem outside the tree. Both sides
        // are resolved, so the firmlink cancels out.
        let resolved = url.resolvingSymlinksInPath().path
        guard roots.contains(where: { atLeastTwoBelow(resolved, root: $0.resolvingSymlinksInPath()) }) else { return false }

        guard let vals = try? std.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              vals.isDirectory == true, vals.isSymbolicLink != true else { return false }

        // A name match also needs a project marker above it, so a smuggled
        // `Artifact(url:)` can't pass on name alone. A `CACHEDIR.TAG` is a
        // deliberate cache marker on its own and needs no project.
        return (isNameAllowlisted(std) && hasProjectAncestor(std, roots: roots)) || hasValidCacheDirTag(std)
    }

    /// Removes each artifact after re-validation. Removal is permanent (these are
    /// regenerable). Freed bytes are only credited once the path is confirmed gone.
    static func delete(_ artifacts: [Artifact], roots: [URL]) -> DeleteResult {
        let fm = FileManager.default
        var result = DeleteResult(freedBytes: 0, failures: [])
        for artifact in artifacts {
            guard isDeletableArtifact(artifact.url, roots: roots) else {
                result.failures.append((artifact.url, "failed safety validation"))
                continue
            }
            do {
                try fm.removeItem(at: artifact.url)
            } catch {
                result.failures.append((artifact.url, error.localizedDescription))
                continue
            }
            if fm.fileExists(atPath: artifact.url.path) {
                result.failures.append((artifact.url, "path still present after removal"))
            } else {
                result.freedBytes += artifact.sizeBytes
            }
        }
        return result
    }

    // MARK: Helpers

    static func hasProjectIndicator(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return projectIndicators.contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    /// Whether a path lives in a Vitals data dir (`~/.vitals*`) or the app's own
    /// Application Support folder — never scanned, never deleted.
    private static func isVitalsPath(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        if components.contains(where: { $0.hasPrefix(".vitals") }) { return true }
        for index in components.indices.dropLast() where components[index] == "Application Support" {
            let next = components[index + 1]
            if next == "Vitals" || next.hasPrefix("Vitals ") { return true }
        }
        return false
    }

    /// Whether an ancestor of `url`, from its parent up to the first component
    /// under its root, carries a project indicator. The scan root itself (e.g.
    /// `~/Code`) never counts.
    private static func hasProjectAncestor(_ url: URL, roots: [URL]) -> Bool {
        guard let root = roots.first(where: { atLeastTwoBelow(url.path, root: $0) }) else { return false }
        let rootPath = root.standardizedFileURL.path
        var dir = url.deletingLastPathComponent().standardizedFileURL
        while true {
            if hasProjectIndicator(dir) { return true }
            let parent = dir.deletingLastPathComponent()
            if parent.path == rootPath { return false }   // dir was the first component under root
            dir = parent
        }
    }

    private static func atLeastTwoBelow(_ path: String, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return false }
        let rest = path.dropFirst(rootPath.count + 1)
        return rest.split(separator: "/", omittingEmptySubsequences: true).count >= 2
    }

    /// Re-checks the name-and-gate side of the artifact rules for `delete`.
    /// Carthage is accepted only as its `Build` subdirectory.
    private static func isNameAllowlisted(_ url: URL) -> Bool {
        let fm = FileManager.default
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent()
        switch name {
        case let name where Self.ungatedArtifactNames.contains(name):
            return true
        case "target":
            return fm.fileExists(atPath: parent.appendingPathComponent("Cargo.toml").path)
        case "Pods":
            return fm.fileExists(atPath: parent.appendingPathComponent("Podfile").path)
        case "dist", "build", "out":
            return hasProjectIndicator(parent)
        case "Build":
            return parent.lastPathComponent == "Carthage"
        default:
            return false
        }
    }

    private static func hasValidCacheDirTag(_ dir: URL) -> Bool {
        let tag = dir.appendingPathComponent("CACHEDIR.TAG")
        guard let handle = try? FileHandle(forReadingFrom: tag) else { return false }
        defer { try? handle.close() }
        let signature = Data(cacheDirSignature.utf8)
        guard let data = try? handle.read(upToCount: signature.count) else { return false }
        return data == signature
    }
}
