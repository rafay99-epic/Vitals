import Testing
import Foundation
@testable import Vitals

/// The dev-junk scanner deletes build artifacts permanently, so its detection
/// must never mistake a source tree for junk, and its validator must reject any
/// path outside the allowlisted roots or rules.
struct DevJunkScannerTests {
    // MARK: Fixture helpers

    /// A throwaway tree under the temp dir, cleaned up by the test.
    final class Tree {
        let root: URL
        private let fm = FileManager.default
        init() {
            root = fm.temporaryDirectory.appendingPathComponent("vitals-devjunk-\(UUID().uuidString)", isDirectory: true)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? fm.removeItem(at: root) }

        @discardableResult
        func dir(_ relative: String) -> URL {
            let url = root.appendingPathComponent(relative, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func file(_ relative: String, _ contents: String = "x") {
            let url = root.appendingPathComponent(relative)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Every artifact URL found across all returned projects.
    private func artifactURLs(_ projects: [DevJunkScanner.Project]) -> [URL] {
        projects.flatMap { $0.artifacts.map(\.url) }
    }
    private func containsArtifact(_ projects: [DevJunkScanner.Project], named name: String) -> Bool {
        artifactURLs(projects).contains { $0.lastPathComponent == name }
    }

    // MARK: (1) source directories are never candidates

    @Test func sourceDirectoriesAreNeverCandidates() {
        let tree = Tree()
        tree.file("proj/package.json")
        tree.dir("proj/src")
        tree.dir("proj/Sources")
        tree.file("proj/src/index.js")
        let projects = DevJunkScanner.scan(roots: [tree.root])
        #expect(!containsArtifact(projects, named: "src"))
        #expect(!containsArtifact(projects, named: "Sources"))
    }

    // MARK: (2) dist needs a project marker in its parent

    @Test func distRequiresProjectMarkerInParent() {
        let bare = Tree()
        bare.dir("randomFolder/dist/assets")     // no project marker anywhere
        #expect(!containsArtifact(DevJunkScanner.scan(roots: [bare.root]), named: "dist"))

        let real = Tree()
        real.file("proj/package.json")
        real.dir("proj/dist/assets")             // parent (proj) is a project
        #expect(containsArtifact(DevJunkScanner.scan(roots: [real.root]), named: "dist"))
    }

    // MARK: (3) target needs a sibling Cargo.toml

    @Test func targetRequiresSiblingCargoToml() {
        let noCargo = Tree()
        noCargo.file("proj/package.json")        // a project, but not a Rust one
        noCargo.dir("proj/target/debug")
        #expect(!containsArtifact(DevJunkScanner.scan(roots: [noCargo.root]), named: "target"))

        let rust = Tree()
        rust.file("proj/Cargo.toml")
        rust.dir("proj/target/debug")
        #expect(containsArtifact(DevJunkScanner.scan(roots: [rust.root]), named: "target"))
    }

    // MARK: (4) Pods needs a sibling Podfile

    @Test func podsRequiresSiblingPodfile() {
        let noPodfile = Tree()
        noPodfile.file("proj/package.json")
        noPodfile.dir("proj/Pods/Alamofire")
        #expect(!containsArtifact(DevJunkScanner.scan(roots: [noPodfile.root]), named: "Pods"))

        let withPodfile = Tree()
        withPodfile.file("proj/Podfile")
        withPodfile.dir("proj/Pods/Alamofire")
        #expect(containsArtifact(DevJunkScanner.scan(roots: [withPodfile.root]), named: "Pods"))
    }

    // MARK: (5) symlinked artifacts are skipped, never followed

    @Test func symlinkNamedNodeModulesIsSkipped() throws {
        let tree = Tree()
        tree.file("proj/package.json")
        let realTarget = tree.dir("elsewhere/actualdeps")
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("proj/node_modules"),
            withDestinationURL: realTarget)

        let projects = DevJunkScanner.scan(roots: [tree.root])
        // The symlink must not be reported, and its destination must not be walked into.
        #expect(!artifactURLs(projects).contains { $0.path.contains("proj/node_modules") })
    }

    // MARK: (6) nested artifacts collapse to the outermost

    @Test func nestedArtifactIsDedupedToOutermost() {
        let tree = Tree()
        tree.file("proj/package.json")
        tree.dir("proj/node_modules/somepkg/android/build")
        let projects = DevJunkScanner.scan(roots: [tree.root])
        let urls = artifactURLs(projects)
        #expect(urls.contains { $0.lastPathComponent == "node_modules" })
        // The inner android/build must not appear as a separate artifact.
        #expect(!urls.contains { $0.path.contains("node_modules/somepkg/android/build") })
        #expect(urls.filter { $0.path.contains("proj/node_modules") }.count == 1)
    }

    // MARK: (7) monorepo attribution to the nearest project

    @Test func monorepoAttributesToNearestProject() {
        let tree = Tree()
        tree.file("mono/package.json")               // outer project
        tree.file("mono/apps/web/package.json")      // inner project
        tree.dir("mono/apps/web/node_modules/react")

        let projects = DevJunkScanner.scan(roots: [tree.root])
        let owner = projects.first { project in
            project.artifacts.contains { $0.kindName == "node_modules" }
        }
        let web = tree.root.appendingPathComponent("mono/apps/web").standardizedFileURL
        #expect(owner?.root.standardizedFileURL == web)
    }

    // MARK: (8) CACHEDIR.TAG gating by signature

    @Test func cacheDirTagIsFoundOnlyWithCorrectSignature() {
        let good = Tree()
        good.file("proj/package.json")
        good.dir("proj/somecache")
        good.file("proj/somecache/CACHEDIR.TAG",
                  "Signature: 8a477f597d28d172789f06886806bc55\n# tagged cache")
        #expect(containsArtifact(DevJunkScanner.scan(roots: [good.root]), named: "somecache"))

        let bad = Tree()
        bad.file("proj/package.json")
        bad.dir("proj/somecache")
        bad.file("proj/somecache/CACHEDIR.TAG", "Signature: deadbeef not the real one")
        #expect(!containsArtifact(DevJunkScanner.scan(roots: [bad.root]), named: "somecache"))
    }

    // MARK: (9) isDeletableArtifact rejects unsafe inputs

    @Test func isDeletableArtifactRejectsUnsafeInputs() {
        let tree = Tree()
        tree.file("proj/package.json")
        let nodeModules = tree.dir("proj/node_modules")
        tree.dir("proj/src")
        tree.file("proj/loose.txt")
        let roots = [tree.root]

        // The good case, to anchor the negatives.
        #expect(DevJunkScanner.isDeletableArtifact(nodeModules, roots: roots))

        // Outside every root.
        #expect(!DevJunkScanner.isDeletableArtifact(
            URL(fileURLWithPath: "/tmp/other/node_modules"), roots: roots))
        // The system volume.
        #expect(!DevJunkScanner.isDeletableArtifact(
            URL(fileURLWithPath: "/System/Library/node_modules"), roots: roots))
        // A traversal path.
        #expect(!DevJunkScanner.isDeletableArtifact(
            tree.root.appendingPathComponent("proj/../../etc/node_modules"), roots: roots))
        // A plain file, not a directory.
        #expect(!DevJunkScanner.isDeletableArtifact(
            tree.root.appendingPathComponent("proj/loose.txt"), roots: roots))
        // A root itself.
        #expect(!DevJunkScanner.isDeletableArtifact(tree.root, roots: roots))
        // A non-allowlisted directory name.
        #expect(!DevJunkScanner.isDeletableArtifact(
            tree.root.appendingPathComponent("proj/src"), roots: roots))
    }

    // MARK: (9a) isDeletableArtifact requires a project ancestor for name-allowlisted artifacts

    @Test func isDeletableArtifactRequiresProjectAncestorForNameAllowlist() {
        // No project indicator anywhere in the tree — an allowlisted name alone
        // must not be enough (closes off a smuggled Artifact(url:) bypass).
        let noIndicator = Tree()
        let orphan = noIndicator.dir("misc/node_modules")
        #expect(!DevJunkScanner.isDeletableArtifact(orphan, roots: [noIndicator.root]))

        // A project indicator directly above the artifact — still accepted.
        let withIndicator = Tree()
        withIndicator.file("proj/package.json")
        let owned = withIndicator.dir("proj/node_modules")
        #expect(DevJunkScanner.isDeletableArtifact(owned, roots: [withIndicator.root]))

        // Nested: repo carries the indicator, sub does not. `dist` still requires
        // the indicator in its *direct* parent (the pre-existing rule) — an
        // indicator two levels up doesn't satisfy that rule, so this stays
        // rejected regardless of the new ancestor gate.
        let nested = Tree()
        nested.dir("repo/.git")
        nested.dir("repo/sub/dist")
        #expect(!DevJunkScanner.isDeletableArtifact(
            nested.root.appendingPathComponent("repo/sub/dist"), roots: [nested.root]))
    }

    // MARK: (9b) isDeletableArtifact rejects a symlinked intermediate directory

    @Test func rejectsArtifactThroughSymlinkedIntermediate() throws {
        let fm = FileManager.default
        let tree = Tree()
        // A normal artifact under a real path still validates — proves resolving
        // both sides (the data-volume firmlink) doesn't reject legitimate paths.
        tree.file("proj/package.json")
        let real = tree.dir("proj/node_modules")
        #expect(DevJunkScanner.isDeletableArtifact(real, roots: [tree.root]))

        // An outside directory (under no root) that holds a node_modules.
        let outside = fm.temporaryDirectory
            .appendingPathComponent("vitals-devjunk-outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outside.appendingPathComponent("node_modules"),
                               withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        // root/link → outside. `root/link/node_modules` is string-contained in the
        // root (unresolved) but resolves outside it, so it must be rejected.
        let link = tree.root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let smuggled = link.appendingPathComponent("node_modules")
        #expect(!DevJunkScanner.isDeletableArtifact(smuggled, roots: [tree.root]))
    }

    // MARK: (10) delete removes junk, credits exact bytes, refuses smuggled paths

    @Test func deleteRemovesArtifactAndCreditsMeasuredBytes() {
        let tree = Tree()
        tree.file("proj/package.json")
        tree.file("proj/node_modules/pkg/a.js", String(repeating: "x", count: 500))
        tree.file("proj/node_modules/pkg/b.js", String(repeating: "y", count: 300))

        var projects = DevJunkScanner.scan(roots: [tree.root])
        projects = projects.map(DevJunkScanner.measured)
        let artifacts = projects.flatMap(\.artifacts)
        #expect(artifacts.count == 1)
        let expectedBytes = artifacts[0].sizeBytes
        #expect(expectedBytes > 0)

        let result = DevJunkScanner.delete(artifacts, roots: [tree.root])
        #expect(result.failures.isEmpty)
        #expect(result.freedBytes == expectedBytes)
        #expect(!FileManager.default.fileExists(atPath: artifacts[0].url.path))
    }

    @Test func deleteRefusesSmuggledNonAllowlistedPath() {
        let tree = Tree()
        tree.file("proj/package.json")
        let source = tree.dir("proj/src")            // not an artifact
        tree.file("proj/src/index.js")

        let smuggled = DevJunkScanner.Artifact(
            url: source, kindName: "src", sizeBytes: 999, modified: nil)
        let result = DevJunkScanner.delete([smuggled], roots: [tree.root])
        #expect(result.freedBytes == 0)
        #expect(result.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: source.path))   // nothing deleted
    }

    // MARK: (11) hidden dirs are skipped, except allowlisted hidden caches

    @Test func hiddenDirsAreSkippedExceptAllowlistedCaches() {
        let tree = Tree()
        tree.file("proj/package.json")
        tree.dir("proj/.cache/blobs")                // hidden, not an artifact name
        tree.dir("proj/.next/server")               // hidden, allowlisted artifact
        let projects = DevJunkScanner.scan(roots: [tree.root])
        #expect(!containsArtifact(projects, named: ".cache"))
        #expect(containsArtifact(projects, named: ".next"))
    }

    // MARK: (12) depth bound

    @Test func artifactBeyondDepthLimitIsNotFound() {
        let tree = Tree()
        tree.file("package.json")                    // the root is the project
        // node_modules eight components below the root — past the six-level bound.
        tree.dir("l1/l2/l3/l4/l5/l6/l7/node_modules")
        let projects = DevJunkScanner.scan(roots: [tree.root])
        #expect(!containsArtifact(projects, named: "node_modules"))
    }

    // MARK: defaultRoots

    @Test func defaultRootsReturnsExistingNonSymlinkDirs() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("vitals-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: home) }
        try fm.createDirectory(at: home.appendingPathComponent("Code"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        // A symlinked "Developer" must be skipped.
        try fm.createSymbolicLink(at: home.appendingPathComponent("Developer"),
                                  withDestinationURL: home.appendingPathComponent("Code"))

        let roots = DevJunkScanner.defaultRoots(home: home).map(\.lastPathComponent)
        #expect(roots.contains("Code"))
        #expect(roots.contains("Documents"))
        #expect(!roots.contains("Developer"))        // symlink skipped
        #expect(!roots.contains("Projects"))         // doesn't exist
    }
}
