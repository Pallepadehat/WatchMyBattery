import Foundation
import Testing

@testable import BatteryKit

struct BatteryHistoryTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let safari = BatteryHistory.AppIdentity(name: "Safari", bundleIdentifier: "com.apple.Safari")
    private let xcode = BatteryHistory.AppIdentity(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")

    private func snapshot(_ percentage: Int, pluggedIn: Bool) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery,
            chargeState: pluggedIn ? .charging : .discharging, timeRemaining: nil)
    }

    private func minutes(_ count: Double) -> Date { start.addingTimeInterval(count * 60) }

    @Test func recordsOnlyChanges() {
        var history = BatteryHistory()
        history.record(snapshot(80, pluggedIn: false), at: minutes(0))
        history.record(snapshot(80, pluggedIn: false), at: minutes(1))
        history.record(snapshot(79, pluggedIn: false), at: minutes(2))
        #expect(history.levels.map(\.percentage) == [80, 79])
    }

    @Test func timeOnBatteryStartsWhenUnplugged() {
        var history = BatteryHistory()
        history.record(snapshot(100, pluggedIn: true), at: minutes(0))
        history.record(snapshot(100, pluggedIn: false), at: minutes(10))
        history.record(snapshot(90, pluggedIn: false), at: minutes(130))

        let stretch = history.sinceUnplugged(snapshot(90, pluggedIn: false), now: minutes(130))
        #expect(stretch?.since == minutes(10))
        #expect(abs((stretch?.duration ?? 0) - 2 * 3600) < 0.001)
        #expect(stretch?.used == 10)
        #expect(abs((stretch?.perHour ?? 0) - 5) < 0.001)

        // Plugged in: no stretch.
        history.record(snapshot(90, pluggedIn: true), at: minutes(140))
        #expect(history.sinceUnplugged(snapshot(90, pluggedIn: true), now: minutes(140)) == nil)
    }

    @Test func noRateUntilThereIsEnoughToGoOn() {
        var history = BatteryHistory()
        history.record(snapshot(100, pluggedIn: true), at: minutes(0))
        history.record(snapshot(100, pluggedIn: false), at: minutes(1))
        #expect(history.sinceUnplugged(snapshot(99, pluggedIn: false), now: minutes(6))?.perHour == nil)
    }

    @Test func unknownUnplugTimeOnFirstLaunchAndAfterChargingUnseen() {
        var history = BatteryHistory()
        history.record(snapshot(70, pluggedIn: false), at: minutes(0))
        #expect(history.sinceUnplugged(snapshot(70, pluggedIn: false), now: minutes(5)) == nil)

        history.record(snapshot(100, pluggedIn: true), at: minutes(10))
        history.record(snapshot(99, pluggedIn: false), at: minutes(20))
        #expect(history.unplugged?.date == minutes(20))
        // The app wasn't running while it charged back up.
        history.record(snapshot(95, pluggedIn: false), at: minutes(60))
        history.record(snapshot(100, pluggedIn: false), at: minutes(600))
        #expect(history.unplugged == nil)
    }

    @Test func pluggedInPeriods() {
        var history = BatteryHistory()
        history.record(snapshot(50, pluggedIn: false), at: minutes(0))
        history.record(snapshot(50, pluggedIn: true), at: minutes(30))
        history.record(snapshot(80, pluggedIn: false), at: minutes(90))
        history.record(snapshot(79, pluggedIn: true), at: minutes(120))

        let periods = history.pluggedInPeriods(since: minutes(0), now: minutes(150))
        #expect(periods == [DateInterval(start: minutes(30), end: minutes(90)), DateInterval(start: minutes(120), end: minutes(150))])
    }

    @Test func levelsStartAtTheEdgeOfTheRange() {
        var history = BatteryHistory()
        history.record(snapshot(90, pluggedIn: false), at: minutes(0))
        history.record(snapshot(80, pluggedIn: false), at: minutes(60))
        let points = history.levels(since: minutes(30))
        #expect(points.map(\.date) == [minutes(30), minutes(60)])
        #expect(points.map(\.percentage) == [90, 80])
        // Nothing since: the last level still holds.
        #expect(history.levels(since: minutes(90)).map(\.percentage) == [80])
    }

    @Test func dropsWhatsOlderThanADay() {
        var history = BatteryHistory()
        history.record(snapshot(90, pluggedIn: false), at: minutes(0))
        history.record(snapshot(80, pluggedIn: false), at: minutes(60))
        history.record(joules: [safari: 100], seconds: 300, systemWatts: 10, at: minutes(60))
        history.record(snapshot(70, pluggedIn: false), at: minutes(25 * 60))
        history.record(snapshot(60, pluggedIn: false), at: minutes(26 * 60))

        // One reading from before the day is kept, so the chart knows where it started.
        #expect(history.levels.map(\.percentage) == [80, 70, 60])
        #expect(history.samples.isEmpty)
        #expect(history.apps.isEmpty)
    }

    @Test func appEnergyAddsUpAndCostsBatteryTime() {
        var history = BatteryHistory()
        history.record(joules: [safari: 600, xcode: 900], seconds: 300, systemWatts: 10, at: minutes(5))
        history.record(joules: [safari: 600], seconds: 300, systemWatts: 10, at: minutes(10))

        let energy = history.appEnergy(since: minutes(0))
        #expect(energy.map(\.app) == [safari, xcode])
        #expect(energy.map(\.joules) == [1200, 900])
        // 1,200 J at an average of 10 W is two minutes of battery.
        #expect(energy.first?.batteryTime == 120)

        // A sample that began before the start counts for the part after it.
        #expect(history.appEnergy(since: minutes(7.5)).first?.joules == 300)
        #expect(history.sampledTime(since: minutes(7.5)) == 150)
    }

    @Test func keepsOnlyTheHungriestAppsOfASample() {
        var history = BatteryHistory()
        var joules: [BatteryHistory.AppIdentity: Double] = [:]
        for index in 0..<30 { joules[BatteryHistory.AppIdentity(name: "App \(index)", bundleIdentifier: nil)] = Double(index + 1) }
        history.record(joules: joules, seconds: 300, systemWatts: nil, at: minutes(5))
        #expect(history.samples.first?.joules.count == BatteryHistory.appsPerSample)
        #expect(history.appEnergy(since: minutes(0)).first?.app.name == "App 29")
        #expect(history.appEnergy(since: minutes(0)).first?.batteryTime == nil)
    }

    @Test func savesAndLoads() throws {
        var history = BatteryHistory()
        let now = Date()
        history.record(snapshot(100, pluggedIn: true), at: now.addingTimeInterval(-600))
        history.record(snapshot(99, pluggedIn: false), at: now.addingTimeInterval(-300))
        history.record(joules: [safari: 42], seconds: 300, systemWatts: 8, at: now)

        let url = FileManager.default.temporaryDirectory.appending(path: "BatteryHistoryTests-\(UUID().uuidString)/history.plist")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try history.save(to: url)
        #expect(BatteryHistory.load(from: url) == history)
        #expect(BatteryHistory.load(from: url.appending(path: "missing")).isEmpty)
    }

    @Test func bucketsHoldTheLevelAtTheirEndAndMarkTimePluggedIn() {
        var history = BatteryHistory()
        let now = minutes(24 * 60)
        // Unplugged at 90% 3 hours ago, down to 80% an hour later, plugged in for the last half hour.
        history.record(snapshot(90, pluggedIn: false), at: minutes(21 * 60))
        history.record(snapshot(80, pluggedIn: false), at: minutes(22 * 60))
        history.record(snapshot(80, pluggedIn: true), at: minutes(23 * 60 + 40))

        let buckets = history.levelBuckets(endingAt: now, count: 48)
        #expect(buckets.count == 48)
        #expect(buckets.first?.start == minutes(0))
        #expect(buckets.last?.end == now)
        // Nothing before history begins.
        #expect(buckets.prefix(42).allSatisfy { $0.percentage == nil && !$0.isPluggedIn })
        #expect(buckets[42].percentage == 90)
        #expect(buckets[44].percentage == 80)
        // Readings only come with changes, so the level carries on.
        #expect(buckets[46].percentage == 80 && !buckets[46].isPluggedIn)
        #expect(buckets[47].isPluggedIn)
    }

    @Test func theLastBucketShowsTheLevelNow() {
        var history = BatteryHistory()
        history.record(snapshot(70, pluggedIn: false), at: minutes(0))
        let buckets = history.levelBuckets(endingAt: minutes(60), count: 48, current: snapshot(64, pluggedIn: false))
        #expect(buckets.last?.percentage == 64)
        // An empty history stays empty, whatever the level now.
        #expect(BatteryHistory().levelBuckets(endingAt: minutes(60), current: snapshot(64, pluggedIn: false)).allSatisfy { $0.percentage == nil })
    }
}
