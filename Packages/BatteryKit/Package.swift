// swift-tools-version: 6.0
import PackageDescription

/// The parts of WatchMyBattery that don't need a UI: reading the battery,
/// measuring how much energy each app uses, and the arithmetic that turns
/// that into "time left" estimates. Kept separate so it can be tested with
/// `swift test`.
let package = Package(
    name: "BatteryKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BatteryKit", targets: ["BatteryKit"])
    ],
    targets: [
        .target(name: "BatteryKit", linkerSettings: [.linkedFramework("IOKit")]),
        .testTarget(name: "BatteryKitTests", dependencies: ["BatteryKit"]),
    ]
)
