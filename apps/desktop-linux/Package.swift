// swift-tools-version: 6.0
import PackageDescription

// Vitals for Linux — native Swift + GTK4/libadwaita, monitoring only.
//
// The package is split so the hardware-reading logic stays portable:
//   • VitalsCore — pure Foundation. Reads /sys and /proc, parses fixtures.
//     Builds and unit-tests on ANY platform (incl. the macOS dev box via
//     `swift test`), because it never touches GTK.
//   • Vitals — the GTK executable. Imports Adwaita (declarative GNOME UI) and
//     CCairo (sparkline rendering). Linux only; verified in CI on ubuntu.
//
// The GTK targets and the Adwaita dependency are gated behind `#if os(Linux)`.
// SwiftPM evaluates this manifest on the BUILD HOST, so a macOS dev machine sees
// only VitalsCore + its tests (and `swift test` builds just those), while CI and
// the Dockerfile — both Linux — see the full graph. This is what lets the pure
// parser logic be tested without a GTK toolchain present.
//
// Adwaita is pinned to the archived GitHub mirror (frozen at 0.2.6) for
// reproducible CI fetches; the project has since moved to git.aparoksha.dev.

var targets: [Target] = [
    .target(
        name: "VitalsCore",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "VitalsCoreTests",
        dependencies: ["VitalsCore"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
]
var products: [Product] = []
var dependencies: [Package.Dependency] = []

#if os(Linux)
products.append(.executable(name: "Vitals", targets: ["Vitals"]))
dependencies.append(.package(url: "https://github.com/AparokshaUI/Adwaita", from: "0.2.0"))
// Cairo draws the dashboard sparklines to PNG — Adwaita's `Picture` decodes
// raster data only. Cairo ships with GTK, so this adds no runtime weight.
targets.append(.systemLibrary(
    name: "CCairo",
    path: "Sources/CCairo",
    pkgConfig: "cairo",
    providers: [.apt(["libcairo2-dev"])]
))
// GIO/GLib for the StatusNotifierItem tray over D-Bus. Ships with GTK.
targets.append(.systemLibrary(
    name: "CGio",
    path: "Sources/CGio",
    pkgConfig: "gio-2.0",
    providers: [.apt(["libglib2.0-dev"])]
))
targets.append(.executableTarget(
    name: "Vitals",
    dependencies: [
        "VitalsCore",
        "CCairo",
        "CGio",
        .product(name: "Adwaita", package: "Adwaita")
    ],
    swiftSettings: [.swiftLanguageMode(.v5)]
))
#endif

let package = Package(
    name: "Vitals",
    // Only satisfies SwiftPM's macOS platform graph on a dev box; no effect on Linux.
    platforms: [.macOS(.v13)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
