// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.macOS(.v15)],
    dependencies: [.package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.31.0")],
    targets: [
        .target(name: "PrivateSensors"),
        .executableTarget(
            name: "Vitals",
            dependencies: ["PrivateSensors", .product(name: "Sentry", package: "sentry-cocoa")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // libsqlite3 ships with macOS: `import SQLite3` against it keeps the
            // history store dependency-free. Sentry stays the only package.
            linkerSettings: [.linkedFramework("IOKit"), .linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "VitalsTests",
            dependencies: ["Vitals"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
