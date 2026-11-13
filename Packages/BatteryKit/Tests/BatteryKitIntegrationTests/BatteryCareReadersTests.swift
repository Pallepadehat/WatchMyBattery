import Foundation
import Testing

@testable import BatteryKit

/// 0.3.0's readers against this Mac: the battery's readings, what keeps it awake, and macOS's charge limit.
@Suite(.tags(.system))
struct BatteryCareReadersTests {
    @Test(.enabled(if: Machine.hasBattery)) func readsTheBatterysVoltageCurrentAndTemperature() {
        let readings = BatteryReadingsReader().read()
        // A laptop battery sits between about 9 and 13.5 volts.
        let voltage = readings.voltage ?? 0
        #expect(voltage > 6 && voltage < 20)
        #expect(readings.current.map { abs($0) < 15 } ?? false)
        // Read from the registry, or the SMC on macOS versions that moved it there.
        #expect(readings.temperature.map { $0 > 0 && $0 < 70 } ?? false)
    }

    @Test func readsAssertionsWithoutMacOSsOwn() {
        let assertions = PowerAssertionReader.read()
        #expect(!assertions.contains { $0.processName == "WindowServer" })
        #expect(!assertions.contains { $0.reason.hasPrefix("Powerd - Prevent sleep while display is on") })
    }

    /// Only reads: the test never changes the Mac's charge limit.
    @Test(.enabled(if: Machine.hasBattery)) func readsTheChargeLimitWhereMacOSHasOne() {
        let client = ChargeLimitClient(clientName: "WatchMyBatteryTests")
        guard let levels = client.levels(), !levels.choices.isEmpty else { return }
        #expect(levels.choices.contains(100))
        #expect(levels.choices.allSatisfy { (1...100).contains($0) })
        let current = client.current()
        #expect(current.map(levels.choices.contains) ?? false)
    }

    @Test func listsProcessesByTheirExecutablesName() {
        #expect(ProcessName.of(getpid()).isEmpty == false)
        #expect(ProcessName.of(1) == "launchd")
    }
}
