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
            linkerSettings: [.linkedFramework("IOKit")]
        ),
    ]
)
