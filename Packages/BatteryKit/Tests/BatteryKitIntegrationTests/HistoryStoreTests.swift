import Foundation
import Testing

@testable import BatteryKit

/// The SwiftData store on a real disk, the way the app keeps it in Application Support.
@Suite(.tags(.system))
@MainActor
struct HistoryStoreTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "BatteryKitIntegrationTests-\(UUID().uuidString)")
    private var url: URL { folder.appending(path: "nested/History.store") }
    private let apps = (0..<30).map { BatteryHistory.AppIdentity(name: "App \($0)", bundleIdentifier: $0 % 5 == 0 ? nil : "com.example.\($0)") }

    private func snapshot(_ percentage: Int, pluggedIn: Bool) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery,
            chargeState: pluggedIn ? .charging : .discharging, timeRemaining: nil)
    }

    /// A day of readings, interleaved the way they arrive, ending now so nothing is trimmed on the way back.
    private func recordDay(into store: HistoryStore, saving: Bool = true) throws {
        let start = Date().addingTimeInterval(-BatteryHistory.retention + 60)
        for step in 0..<288 {
            let date = start.addingTimeInterval(Double(step) * 300)
            store.record(snapshot(100 - step % 90, pluggedIn: (120..<160).contains(step)), at: date)
            var joules: [BatteryHistory.AppIdentity: Double] = [:]
            for offset in 0..<18 { joules[apps[(step + offset) % apps.count]] = Double(offset + 1) * 1.5 }
            store.record(joules: joules, seconds: 300, systemWatts: 9, at: date.addingTimeInterval(1))
            // The app saves after every sample.
            if saving { try store.save() }
        }
    }

    @Test func aDaySurvivesARestart() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: url)
        try recordDay(into: store)
        #expect(!store.hasUnsavedChanges)

        let reopened = try HistoryStore(url: url)
        #expect(reopened.history == store.history)
        #expect(reopened.profile.hours == store.profile.hours)
        #expect(reopened.profile.apps == store.profile.apps)
        #expect(reopened.history.unplugged == store.history.unplugged)
        #expect(!reopened.profile.isEmpty)
    }

    /// The store is written to every five minutes on battery; it has to stay small.
    @Test func aDayIsSmallOnDisk() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: url)
        try recordDay(into: store)
        let size = ["", "-wal", "-shm"].compactMap {
            try? FileManager.default.attributesOfItem(atPath: url.path + $0)[.size] as? Int
        }.reduce(0, +)
        #expect(size < 4 * 1024 * 1024, "A day of history takes \(size / 1024) KB")
    }

    @Test func unsavedChangesAreLostAndSavedOnesKept() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: url)
        store.record(snapshot(80, pluggedIn: false), at: Date().addingTimeInterval(-60))
        try store.save()
        store.record(snapshot(79, pluggedIn: false))
        #expect(store.hasUnsavedChanges)
        #expect(try HistoryStore(url: url).history.levels.map(\.percentage) == [80])
    }

    @Test func importsTheOldPropertyList() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let scratch = try HistoryStore(url: nil)
        try recordDay(into: scratch, saving: false)

        let store = try HistoryStore(url: url)
        store.importLegacy(scratch.history)
        try store.save()
        let reopened = try HistoryStore(url: url)
        #expect(reopened.history == scratch.history)
        // The summary is built from the old readings, the same as if they'd been recorded now.
        #expect(reopened.profile.hours == scratch.profile.hours)

        // Never over newer readings.
        var other = BatteryHistory()
        other.record(snapshot(12, pluggedIn: false))
        reopened.importLegacy(other)
        #expect(reopened.history == scratch.history)
    }

    @Test func clearingEmptiesTheDisk() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: url)
        try recordDay(into: store)
        store.removeAll()
        try store.save()
        #expect(try HistoryStore(url: url).isEmpty)
    }

    /// The app starts again from the current level straight after clearing, and records on from there.
    @Test func recordingCarriesOnAfterClearing() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: url)
        try recordDay(into: store)
        store.removeAll()
        store.record(snapshot(40, pluggedIn: false))
        store.record(joules: [apps[2]: 50], seconds: 300, systemWatts: 9)
        try store.save()

        let reopened = try HistoryStore(url: url)
        #expect(reopened.history.levels.map(\.percentage) == [40])
        #expect(reopened.history.samples.count == 1)
        #expect(reopened.profile.hours == store.profile.hours)
        #expect(reopened.profile.apps.keys.sorted() == [apps[2].key])
    }

    @Test func oldReadingsAreTrimmedWhenOpened() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 3600)
        let store = try HistoryStore(url: url, now: threeDaysAgo)
        store.record(snapshot(80, pluggedIn: false), at: threeDaysAgo)
        store.record(snapshot(70, pluggedIn: false), at: threeDaysAgo.addingTimeInterval(600))
        store.record(joules: [apps[1]: 10], seconds: 300, systemWatts: 9, at: threeDaysAgo.addingTimeInterval(600))
        try store.save()

        let reopened = try HistoryStore(url: url)
        // The last level is kept, so the chart knows where it stood; the samples go…
        #expect(reopened.history.levels.map(\.percentage) == [70])
        #expect(reopened.history.samples.isEmpty)
        // …but the two-week summary still has them.
        #expect(reopened.profile.sampledTime(since: threeDaysAgo.addingTimeInterval(-3600)) == 300)
        #expect(reopened.profile.apps[apps[1].key] != nil)
    }

    @Test func aDamagedStoreStartsOver() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: url)
        var problems = 0
        let store = HistoryStore.open(at: url) { _ in problems += 1 }
        #expect(problems == 1)
        #expect(store.isEmpty)
        store.record(snapshot(50, pluggedIn: false))
        try store.save()
        #expect(try HistoryStore(url: url).history.levels.count == 1)
    }

    @Test func newAppMarksAreKept() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: url)
        store.record(joules: [apps[3]: 100], seconds: 300, systemWatts: 9)
        store.markNotifiedAsNew(apps[3].key)
        try store.save()
        #expect(try HistoryStore(url: url).profile.apps[apps[3].key]?.notifiedAsNew != nil)
    }
}
