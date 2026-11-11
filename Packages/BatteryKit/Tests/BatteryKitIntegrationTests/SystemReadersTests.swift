import Foundation
import Testing

@testable import BatteryKit

/// The readers against this Mac's real battery. Tests that need one skip themselves on Macs without (CI's virtual Macs).
@Suite(.tags(.system))
struct SystemReadersTests {
    @Test func readsAConsistentSnapshot() {
        let snapshot = PowerSourceReader.read()
        guard snapshot.hasBattery else {
            #expect(snapshot == .noBattery)
            return
        }
        #expect((0...100).contains(snapshot.percentage))
        switch snapshot.chargeState {
        case .discharging: #expect(snapshot.powerSource == .battery)
        case .charging, .charged, .notCharging: #expect(snapshot.powerSource == .powerAdapter)
        }
        if let timeRemaining = snapshot.timeRemaining {
            // macOS never estimates more than a day or two.
            #expect(timeRemaining > 0 && timeRemaining < 48 * 3600)
        }
        #expect(snapshot.isLowPowerModeOn == ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// The menu bar has to show what macOS shows, so the level is checked against `pmset`, macOS's own tool.
    @Test(.enabled(if: Machine.hasBattery)) func agreesWithPmset() throws {
        let output = try #require(Machine.run("/usr/bin/pmset", ["-g", "batt"]))
        // "-InternalBattery-0 (id=1234)	85%; discharging; 4:12 remaining present: true"
        let match = try #require(output.firstMatch(of: /InternalBattery[^\t]*\t(\d+)%; ([a-zA-Z ]+);/))
        let pmsetPercentage = try #require(Int(match.output.1))
        let snapshot = PowerSourceReader.read()
        // The level can tick over between the two readings.
        #expect(abs(snapshot.percentage - pmsetPercentage) <= 1)
        let onAdapter = output.contains("'AC Power'")
        #expect(snapshot.isPluggedIn == onAdapter)
    }

    @Test(.enabled(if: Machine.hasBattery)) func readsAPlausiblePowerDraw() {
        // A Mac draws something, and no MacBook draws more than its biggest charger delivers.
        if let watts = SystemPowerReader().currentWatts() {
            #expect(watts > 0 && watts < 250)
        } else {
            // Without telemetry there's only the battery's own flow, which is zero on a resting, plugged in battery.
            #expect(PowerSourceReader.read().isPluggedIn)
        }
    }

    @Test(.enabled(if: Machine.hasBattery), .timeLimit(.minutes(1))) func readsBatteryHealth() async throws {
        let health = try #require(await BatteryHealthReader.read())
        #expect(!health.isEmpty)
        if let capacity = health.maximumCapacity { #expect(capacity > 0.3 && capacity <= 1.5) }
        if let cycles = health.cycleCount { #expect(cycles >= 0 && cycles < 10_000) }
    }

    @Test func noBatteryMeansNoPowerReading() {
        guard !Machine.hasBattery else { return }
        #expect(SystemPowerReader().currentWatts() == nil)
    }

    @Test @MainActor func observerStartsAndStopsCleanly() {
        var calls = 0
        let observer = PowerSourceObserver { calls += 1 }
        observer.start()
        observer.start()  // A second start is ignored rather than adding a second source.
        observer.stop()
        observer.stop()
        #expect(calls == 0)
    }
}

extension Tag {
    /// Reads the real battery, kernel or disk.
    @Tag static var system: Self
}

enum Machine {
    static let hasBattery = PowerSourceReader.read().hasBattery

    /// Runs a command and returns what it printed, or `nil` if it failed.
    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
