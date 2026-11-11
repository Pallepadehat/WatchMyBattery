import Foundation
import Testing

@testable import BatteryKit

/// The history on a real disk, the way the app keeps it in Application Support.
@Suite(.tags(.system))
struct HistoryStorageTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "BatteryKitIntegrationTests-\(UUID().uuidString)")
    private var file: URL { folder.appending(path: "nested/History.plist") }

    private func snapshot(_ percentage: Int, pluggedIn: Bool) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery,
            chargeState: pluggedIn ? .charging : .discharging, timeRemaining: nil)
    }

    /// A full day, ending now so loading doesn't trim it.
    private func fullDay() -> BatteryHistory {
        var history = BatteryHistory()
        let start = Date().addingTimeInterval(-BatteryHistory.retention + 60)
        for step in 0..<300 {
            history.record(snapshot(100 - step % 90, pluggedIn: (120..<160).contains(step)), at: start.addingTimeInterval(Double(step) * 280))
        }
        let apps = (0..<30).map { BatteryHistory.AppIdentity(name: "App \($0)", bundleIdentifier: $0 % 5 == 0 ? nil : "com.example.\($0)") }
        for index in 0..<280 {
            var joules: [BatteryHistory.AppIdentity: Double] = [:]
            for offset in 0..<18 { joules[apps[(index + offset) % apps.count]] = Double(offset + 1) * 1.5 }
            history.record(joules: joules, seconds: 300, systemWatts: 9, at: start.addingTimeInterval(Double(index + 1) * 300))
        }
        return history
    }

    @Test func savesAFullDayAndReadsItBack() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = fullDay()
        try history.save(to: file)
        let loaded = BatteryHistory.load(from: file)
        #expect(loaded == history)
        #expect(loaded.samples.count == 280)
        #expect(loaded.samples.allSatisfy { $0.joules.count <= BatteryHistory.appsPerSample })
    }

    /// The file stays small: it's rewritten every five minutes on battery.
    @Test func aFullDayIsSmallOnDisk() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try fullDay().save(to: file)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        #expect(size < 512 * 1024, "A day of history takes \(size / 1024) KB")
    }

    @Test func savingReplacesTheFileWhole() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try fullDay().save(to: file)
        var small = BatteryHistory()
        small.record(snapshot(50, pluggedIn: false))
        try small.save(to: file)
        #expect(BatteryHistory.load(from: file) == small)
    }

    @Test func aDamagedFileLoadsAsEmpty() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try fullDay().save(to: file)
        let data = try Data(contentsOf: file)
        try data.prefix(data.count / 2).write(to: file)
        #expect(BatteryHistory.load(from: file).isEmpty)
    }

    @Test func aMissingFileLoadsAsEmpty() {
        #expect(BatteryHistory.load(from: folder.appending(path: "nothing-here.plist")).isEmpty)
    }

    @Test func anOldDayIsTrimmedOnLoad() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var history = BatteryHistory()
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 3600)
        history.record(snapshot(80, pluggedIn: false), at: twoDaysAgo)
        history.record(
            joules: [BatteryHistory.AppIdentity(name: "Old", bundleIdentifier: nil): 10], seconds: 300, systemWatts: 9, at: twoDaysAgo)
        try history.save(to: file)

        let loaded = BatteryHistory.load(from: file)
        #expect(loaded.samples.isEmpty)
        #expect(loaded.apps.isEmpty)
        // The last level is kept, so the chart knows where it stood.
        #expect(loaded.levels.count == 1)
    }

    /// The whole path the app takes: measure the real processes, record them, save, and read them back.
    @Test(.enabled(if: EnergySamplingTests.countsEnergy)) func measuredEnergySurvivesARestart() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sampler = ProcessEnergySampler()
        _ = await sampler.sampleEnergy()
        burnCPU(for: .milliseconds(250))
        let (joules, seconds) = await sampler.sampleEnergy()
        let byApp = Dictionary(
            joules.map { (BatteryHistory.AppIdentity(name: "Process \($0.key)", bundleIdentifier: nil), $0.value) }, uniquingKeysWith: +)

        var history = BatteryHistory()
        history.record(snapshot(70, pluggedIn: false))
        history.record(joules: byApp, seconds: seconds, systemWatts: SystemPowerReader().currentWatts())
        try history.save(to: file)

        let loaded = BatteryHistory.load(from: file)
        #expect(loaded == history)
        let ours = "name:Process \(Responsibility.responsiblePID(for: getpid()))"
        let top = loaded.appEnergy(since: Date().addingTimeInterval(-3600))
        #expect(top.contains { $0.id == ours }, "The busy process isn't among the apps that used the most")
        #expect(top.count <= BatteryHistory.appsPerSample)
    }
}
