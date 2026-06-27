// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "PrivateSensors"),
        .executableTarget(
            name: "Vitals",
            dependencies: ["PrivateSensors"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // libsqlite3 ships with macOS — `import SQLite3` against it keeps the
            // history store dependency-free, matching the zero-dependency norm.
            linkerSettings: [.linkedFramework("IOKit"), .linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "VitalsTests",
            dependencies: ["Vitals"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
