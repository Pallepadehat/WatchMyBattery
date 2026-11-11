// swift-tools-version: 6.0
import PackageDescription

/// The parts of WatchMyBattery that don't need a UI: reading the battery,
/// measuring how much energy each app uses, and the arithmetic that turns
/// that into "time left" estimates. Kept separate so it can be tested with
/// `swift test`.
///
/// - `BatteryKitTests`: unit tests, with made-up data. Fast and the same on any Mac.
/// - `BatteryKitIntegrationTests`: against this Mac's real battery, kernel and disk.
///   Tests that need a battery skip themselves on Macs without one (CI's, for one).
/// - `BatteryKitBenchmarks`: `swift run -c release BatteryKitBenchmarks` times the
///   hot paths against budgets and `Benchmarks/baseline.json`.
let package = Package(
    name: "BatteryKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BatteryKit", targets: ["BatteryKit"])
    ],
    targets: [
        .target(name: "BatteryKit", linkerSettings: [.linkedFramework("IOKit")]),
        .testTarget(name: "BatteryKitTests", dependencies: ["BatteryKit"]),
        .testTarget(name: "BatteryKitIntegrationTests", dependencies: ["BatteryKit"]),
        .executableTarget(name: "BatteryKitBenchmarks", dependencies: ["BatteryKit"]),
    ]
)
