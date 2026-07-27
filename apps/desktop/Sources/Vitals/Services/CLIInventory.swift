import Foundation

/// Discovers globally installed command-line tools without treating project
/// dependencies or arbitrary PATH entries as applications. Every removable
/// row comes from a package manager's own inventory and keeps that manager for
/// the eventual uninstall.
enum CLIInventory {
    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let fm = FileManager.default

    static func scan() async -> [InstalledApp] {
        let rows = await withTaskGroup(of: [InstalledApp].self, returning: [[InstalledApp]].self) { group in
            group.addTask { homebrewFormulae() }
            group.addTask { npmPackages() }
            group.addTask { bunPackages() }
            group.addTask { pnpmPackages() }
            group.addTask { yarnPackages() }
            group.addTask { cargoPackages() }
            group.addTask { gemPackages() }
            group.addTask { pipxPackages() }
            group.addTask { uvPackages() }
            group.addTask { goBinaries() }

            var results: [[InstalledApp]] = []
            for await result in group { results.append(result) }
            return results
        }.flatMap { $0 }

        var seen = Set<URL>()
        return rows
            .filter { seen.insert($0.id.standardizedFileURL).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Removes only a row whose package-manager identity and installation path
    /// still match the scan. Go has no per-package uninstall command, so its
    /// individually proven binary is moved to the Trash instead.
    static func uninstall(_ app: InstalledApp) -> Bool {
        guard case .cli(let manager, let packageName, let installLocation) = app.kind,
              owns(app, manager: manager, packageName: packageName, installLocation: installLocation) else {
            return false
        }

        if manager == .go {
            do {
                try fm.trashItem(at: app.id, resultingItemURL: nil)
                return !fm.fileExists(atPath: app.id.path)
            } catch {
                return false
            }
        }

        switch manager {
        case .homebrew:
            return run("brew", args: ["uninstall", "--formula", packageName])?.status == 0
        case .npm:
            return run("npm", args: ["uninstall", "--global", packageName])?.status == 0
        case .bun:
            return run("bun", args: ["remove", "--global", packageName])?.status == 0
        case .pnpm:
            return run("pnpm", args: ["remove", "--global", packageName])?.status == 0
        case .yarn:
            return run("yarn", args: ["global", "remove", packageName])?.status == 0
        case .cargo:
            return run("cargo", args: ["uninstall", "--root", installLocation.path, packageName])?.status == 0
        case .gem:
            return run("gem", args: [
                "uninstall", packageName, "--all", "--executables",
                "--abort-on-dependent", "--install-dir", installLocation.path,
            ])?.status == 0
        case .pipx:
            return run("pipx", args: ["uninstall", packageName])?.status == 0
        case .uv:
            return run("uv", args: ["tool", "uninstall", packageName])?.status == 0
        case .go:
            return false
        }
    }

    // MARK: Homebrew

    private static func homebrewFormulae() -> [InstalledApp] {
        guard let rootResult = run("brew", args: ["--prefix"]), rootResult.status == 0,
              let brewRoot = existingDirectory(from: rootResult.stdout),
              let result = run("brew", args: ["info", "--json=v2", "--installed", "--formula"]),
              let object = jsonObject(from: result.stdout),
              let formulae = object["formulae"] as? [[String: Any]] else { return [] }

        return formulae.compactMap { formula in
            guard let name = formula["name"] as? String,
                  let installed = (formula["installed"] as? [[String: Any]])?.first,
                  let version = installed["version"] as? String else { return nil }
            let prefix = brewRoot.appendingPathComponent("opt", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: prefix.path) else { return nil }
            let resolvedPrefix = prefix.resolvingSymlinksInPath()
            guard isSafeLocation(resolvedPrefix, roots: [URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")]) else { return nil }
            let requested = installed["installed_on_request"] as? Bool ?? true
            return makeCLI(
                id: resolvedPrefix,
                name: name,
                manager: .homebrew,
                packageName: name,
                version: version,
                location: prefix,
                protectedReason: requested ? nil : "Homebrew dependency"
            )
        }
    }

    // MARK: Node package managers

    private static func npmPackages() -> [InstalledApp] {
        guard let rootResult = run("npm", args: ["root", "--global"]),
              let root = existingDirectory(from: rootResult.stdout),
              let result = run("npm", args: ["ls", "--global", "--depth=0", "--json"]),
              let object = jsonObject(from: result.stdout),
              let dependencies = object["dependencies"] as? [String: Any] else { return [] }
        return nodeDependencies(dependencies, root: root, manager: .npm)
    }

    private static func bunPackages() -> [InstalledApp] {
        guard let result = run("bun", args: ["pm", "ls", "--global", "--depth=0"]) else { return [] }
        return parseTreePackages(result.stdout, manager: .bun)
    }

    private static func pnpmPackages() -> [InstalledApp] {
        guard let result = run("pnpm", args: ["ls", "--global", "--depth=0", "--json"]),
              let object = jsonValue(from: result.stdout) else { return [] }
        var rows: [InstalledApp] = []
        collectPNPMDependencies(object, rows: &rows)
        return rows
    }

    private static func yarnPackages() -> [InstalledApp] {
        guard let result = run("yarn", args: ["global", "dir"]),
              let root = existingDirectory(from: result.stdout),
              let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = object["dependencies"] as? [String: Any] else { return [] }
        return nodeDependencies(dependencies, root: root.appendingPathComponent("node_modules"), manager: .yarn)
    }

    private static func nodeDependencies(
        _ dependencies: [String: Any], root: URL, manager: CLIManager
    ) -> [InstalledApp] {
        dependencies.compactMap { name, value in
            guard let detail = value as? [String: Any],
                  let version = detail["version"] as? String else { return nil }
            let packageURL = root.appendingPathComponent(name)
            guard isSafeLocation(packageURL, roots: [root]) else { return nil }
            return makeCLI(
                id: packageURL,
                name: name,
                manager: manager,
                packageName: name,
                version: version,
                location: packageURL
            )
        }
    }

    static func parseTreePackages(_ text: String, manager: CLIManager) -> [InstalledApp] {
        guard let first = text.split(whereSeparator: { $0.isNewline }).first,
              let rootEnd = first.range(of: " ("),
              !first[..<rootEnd.lowerBound].isEmpty else { return [] }
        let root = URL(fileURLWithPath: String(first[..<rootEnd.lowerBound]))
        guard isSafeLocation(root, roots: [root]) else { return [] }
        return text.split(whereSeparator: { $0.isNewline }).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let marker = line.range(of: "── ") else { return nil }
            let spec = String(line[marker.upperBound...])
            guard let at = spec.lastIndex(of: "@"), at > spec.startIndex else { return nil }
            let name = String(spec[..<at])
            let version = String(spec[spec.index(after: at)...])
            let packageURL = root.appendingPathComponent(name)
            guard isSafeLocation(packageURL, roots: [root]) else { return nil }
            return makeCLI(id: packageURL, name: name, manager: manager,
                           packageName: name, version: version, location: packageURL)
        }
    }

    private static func collectPNPMDependencies(_ value: Any, rows: inout [InstalledApp]) {
        guard let object = value as? [String: Any] else {
            if let array = value as? [Any] {
                for item in array { collectPNPMDependencies(item, rows: &rows) }
            }
            return
        }
        if let path = object["path"] as? String,
           let dependencies = object["dependencies"] as? [String: Any] {
            let root = URL(fileURLWithPath: path).appendingPathComponent("node_modules")
            for (name, detail) in dependencies {
                guard let detail = detail as? [String: Any],
                      let version = detail["version"] as? String else { continue }
                let packageURL = root.appendingPathComponent(name)
                guard isSafeLocation(packageURL, roots: [root]) else { continue }
                rows.append(makeCLI(id: packageURL, name: name, manager: .pnpm,
                                    packageName: name, version: version, location: packageURL))
            }
        }
        for child in object.values { collectPNPMDependencies(child, rows: &rows) }
    }

    // MARK: Cargo, RubyGems, Python, and Go

    private static func cargoPackages() -> [InstalledApp] {
        guard let result = run("cargo", args: ["install", "--list"]), result.status == 0 else { return [] }
        let cargoHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CARGO_HOME"] ?? home.appendingPathComponent(".cargo").path)
        let bin = cargoHome.appendingPathComponent("bin")
        var rows: [InstalledApp] = []
        var current: (String, String, [String])?

        func flush() {
            guard let current, let executable = current.2.first else { return }
            let executableURL = bin.appendingPathComponent(executable)
            guard fm.isExecutableFile(atPath: executableURL.path) else { return }
            rows.append(makeCLI(id: executableURL, name: current.0, manager: .cargo,
                                packageName: current.0, version: current.1,
                                location: cargoHome))
        }

        for rawLine in result.stdout.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            if line.hasSuffix(":"), let separator = line.range(of: " v"),
               separator.upperBound < line.index(before: line.endIndex) {
                flush()
                let name = String(line[..<separator.lowerBound])
                let version = String(line[separator.upperBound..<line.index(before: line.endIndex)])
                current = (name, version, [])
            } else if line.hasPrefix("    "), current != nil {
                current!.2 += line.trimmingCharacters(in: .whitespaces).split(separator: ",").map(String.init)
            }
        }
        flush()
        return rows
    }

    private static func gemPackages() -> [InstalledApp] {
        guard let result = run("gem", args: ["env", "home"]),
              let gemHome = existingDirectory(from: result.stdout) else { return [] }
        let gemsRoot = gemHome.appendingPathComponent("gems")
        guard let directories = try? fm.contentsOfDirectory(at: gemsRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return directories.compactMap { directory in
            let bin = directory.appendingPathComponent("bin")
            guard let executables = try? fm.contentsOfDirectory(at: bin, includingPropertiesForKeys: [.isRegularFileKey]),
                  executables.contains(where: { fm.isExecutableFile(atPath: $0.path) }) else { return nil }
            let parts = directory.lastPathComponent.split(separator: "-")
            guard let split = (1..<parts.count).reversed().first(where: { parts[$0].first?.isNumber == true }) else { return nil }
            let name = parts[..<split].joined(separator: "-")
            let version = parts[split...].joined(separator: "-")
            return makeCLI(id: directory, name: name, manager: .gem,
                           packageName: name, version: version,
                           location: gemHome)
        }
    }

    private static func pipxPackages() -> [InstalledApp] {
        guard let result = run("pipx", args: ["list", "--output", "json"]),
              let object = jsonObject(from: result.stdout),
              let venvs = object["venvs"] as? [String: Any] else { return [] }
        return venvs.compactMap { name, value in
            guard let venv = value as? [String: Any],
                  let main = venv["metadata"] as? [String: Any],
                  let package = main["main_package"] as? [String: Any],
                  let version = package["version"] as? String,
                  let locationString = venv["venv_dir"] as? String else { return nil }
            let location = URL(fileURLWithPath: locationString)
            guard isSafeLocation(location, roots: [home]) else { return nil }
            return makeCLI(id: location, name: name, manager: .pipx,
                           packageName: name, version: version, location: location)
        }
    }

    private static func uvPackages() -> [InstalledApp] {
        guard let result = run("uv", args: ["tool", "list", "--show-paths"]), result.status == 0,
              let directoryResult = run("uv", args: ["tool", "dir"]),
              let toolsRoot = existingDirectory(from: directoryResult.stdout) else { return [] }
        return result.stdout.split(whereSeparator: { $0.isNewline }).compactMap { rawLine in
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard let separator = line.range(of: " v") else { return nil }
            let name = String(line[..<separator.lowerBound])
            let version = String(line[separator.upperBound...].split(separator: " ").first ?? "")
            guard !name.isEmpty, !version.isEmpty else { return nil }
            let location = toolsRoot.appendingPathComponent(name)
            guard isSafeLocation(location, roots: [toolsRoot]) else { return nil }
            return makeCLI(id: location, name: name, manager: .uv,
                           packageName: name, version: version, location: location)
        }
    }

    private static func goBinaries() -> [InstalledApp] {
        guard let result = run("go", args: ["env", "GOBIN", "GOPATH"]), result.status == 0 else { return [] }
        let values = result.stdout.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard let gopath = values.last else { return [] }
        let bin = URL(fileURLWithPath: values.first.flatMap { $0.isEmpty ? nil : $0 } ?? (gopath + "/bin"))
        guard isSafeLocation(bin, roots: [home]),
              let files = try? fm.contentsOfDirectory(at: bin, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return files.compactMap { file in
            guard fm.isExecutableFile(atPath: file.path),
                  let version = run("go", args: ["version", "-m", file.path]) else { return nil }
            var module: String?
            var moduleVersion: String?
            for line in version.stdout.split(whereSeparator: { $0.isNewline }) {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if fields.first == "mod", fields.count >= 3 {
                    module = String(fields[1])
                    moduleVersion = String(fields[2])
                }
            }
            guard let module, let moduleVersion else { return nil }
            return makeCLI(id: file, name: module, manager: .go,
                           packageName: module, version: moduleVersion, location: bin)
        }
    }

    // MARK: Ownership and process helpers

    private static func owns(_ app: InstalledApp, manager: CLIManager,
                             packageName: String, installLocation: URL) -> Bool {
        guard app.isCLI, fm.fileExists(atPath: app.id.path),
              isSafeLocation(installLocation, roots: [home, URL(fileURLWithPath: "/opt/homebrew"), URL(fileURLWithPath: "/usr/local")]) else { return false }
        switch manager {
        case .homebrew:
            guard let prefix = run("brew", args: ["--prefix", packageName]), prefix.status == 0 else { return false }
            return URL(fileURLWithPath: prefix.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath() == installLocation.resolvingSymlinksInPath()
        case .npm, .bun, .pnpm, .yarn:
            guard let data = try? Data(contentsOf: app.id.appendingPathComponent("package.json")),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return object["name"] as? String == packageName
        case .cargo:
            return app.id.path.hasPrefix(installLocation.appendingPathComponent("bin").path + "/")
        case .gem:
            return app.id.path.hasPrefix(installLocation.appendingPathComponent("gems").path + "/")
        case .pipx, .uv:
            return app.id.path.hasPrefix(installLocation.path + "/") || app.id.standardizedFileURL == installLocation.standardizedFileURL
        case .go:
            return app.id.path.hasPrefix(installLocation.path + "/")
        }
    }

    private static func makeCLI(
        id: URL, name: String, manager: CLIManager, packageName: String,
        version: String, location: URL, protectedReason: String? = nil
    ) -> InstalledApp {
        let writable = fm.isWritableFile(atPath: location.path)
        return InstalledApp(
            id: id,
            name: name,
            bundleID: nil,
            version: version,
            kind: .cli(manager: manager, packageName: packageName, installLocation: location),
            protectedReason: protectedReason ?? (writable ? nil : "Needs package-manager permissions"),
            requiresAdmin: !writable
        )
    }

    private static func jsonObject(from text: String) -> [String: Any]? {
        guard let value = jsonValue(from: text) as? [String: Any] else { return nil }
        return value
    }

    private static func jsonValue(from text: String) -> Any? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))
    }

    private static func existingDirectory(from output: String) -> URL? {
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: path)
        var isDirectory = ObjCBool(false)
        return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : nil
    }

    private static func isSafeLocation(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        guard !path.isEmpty, path != "/", path != home.path else { return false }
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private static func run(_ name: String, args: [String]) -> CommandResult? {
        guard let executable = executable(named: name) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        let output = Pipe()
        process.standardOutput = output
        // Drain stdout before waiting for exit. Large inventories (notably
        // Homebrew's JSON output) can fill a pipe and otherwise deadlock.
        process.standardError = FileHandle.standardError
        do { try process.run() } catch { return nil }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: stdout, encoding: .utf8) ?? "",
            stderr: ""
        )
    }

    private static func executable(named name: String) -> String? {
        var paths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        paths += [
            "/opt/homebrew/bin", "/usr/local/bin",
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
        ]
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(at: nvm, includingPropertiesForKeys: [.isDirectoryKey]) {
            paths += versions.map { $0.appendingPathComponent("bin").path }
        }
        for directory in paths {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
