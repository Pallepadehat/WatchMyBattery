import Foundation
import Testing

@testable import BatteryKit

struct UsageProfileTests {
    /// On the hour, so hours line up with the readings.
    private let start = UsageProfile.hourStart(of: Date(timeIntervalSinceReferenceDate: 800_000_000))
    private let xcode = BatteryHistory.AppIdentity(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
    private let safari = BatteryHistory.AppIdentity(name: "Safari", bundleIdentifier: "com.apple.Safari")

    private func minutes(_ count: Double) -> Date { start.addingTimeInterval(count * 60) }
    private func level(_ percentage: Int, pluggedIn: Bool = false, at date: Date) -> BatteryHistory.LevelPoint {
        .init(date: date, percentage: percentage, isPluggedIn: pluggedIn)
    }

    @Test func countsTimeAndDrainOnBatteryByHour() {
        var profile = UsageProfile()
        profile.record(level: level(100, pluggedIn: true, at: minutes(0)))
        profile.record(level: level(100, at: minutes(30)))  // unplugged
        profile.record(level: level(90, at: minutes(90)))
        profile.record(level: level(85, pluggedIn: true, at: minutes(100)))  // plugged in
        profile.record(level: level(95, pluggedIn: true, at: minutes(150)))

        #expect(profile.hours.count == 2)
        // 30 minutes on battery in the first hour, 40 in the second; the plugged-in time doesn't count.
        #expect(profile.hours[0].batterySeconds == 30 * 60)
        #expect(profile.hours[1].batterySeconds == 40 * 60)
        // 10 points used on battery; the drop as it was plugged in counts as battery used too, charging doesn't.
        #expect(profile.hours.map(\.drained) == [0, 10])
    }

    @Test func aNightAsleepSpreadsItsDrainOverTheNight() {
        var profile = UsageProfile()
        profile.record(level: level(80, at: minutes(0)))
        profile.record(level: level(72, at: minutes(8 * 60)))
        #expect(profile.hours.count == 8)
        #expect(profile.hours.allSatisfy { $0.batterySeconds == 3600 && $0.drained == 1 })
    }

    @Test func daysWithoutTheAppRunningAreNotCounted() {
        var profile = UsageProfile()
        profile.record(level: level(80, at: minutes(0)))
        profile.record(level: level(40, at: minutes(3 * 24 * 60)))
        #expect(profile.isEmpty)
    }

    @Test func aSampleSpanningSleepHasNoPowerReading() {
        var profile = UsageProfile()
        let sample = BatteryHistory.EnergySample(date: minutes(8 * 60), seconds: 8 * 3600, joules: [xcode.key: 800], systemWatts: 12)
        profile.record(sample, apps: [xcode.key: xcode])
        #expect(profile.hours.allSatisfy { $0.measuredSeconds == 0 && $0.sampledSeconds == 3600 })
        #expect(profile.appEnergy(since: start).first?.joules == 800)
    }

    @Test func splitsASampleAcrossTheHoursItCovers() {
        var profile = UsageProfile()
        let sample = BatteryHistory.EnergySample(date: minutes(65), seconds: 10 * 60, joules: [xcode.key: 600], systemWatts: 10)
        profile.record(sample, apps: [xcode.key: xcode])

        #expect(profile.hours.count == 2)
        #expect(profile.hours[0].sampledSeconds == 5 * 60)
        #expect(profile.hours[0].appJoules[xcode.key] == 300)
        #expect(profile.hours[1].systemJoules == 10 * 5 * 60)
        #expect(profile.hours[1].averageWatts == 10)
        #expect(profile.apps[xcode.key]?.firstSeen == minutes(65))
    }

    @Test func keepsTwoWeeks() {
        var profile = UsageProfile()
        profile.record(BatteryHistory.EnergySample(date: minutes(5), seconds: 300, joules: [safari.key: 30], systemWatts: 8), apps: [safari.key: safari])
        let later = minutes(15 * 24 * 60)
        profile.record(BatteryHistory.EnergySample(date: later, seconds: 300, joules: [xcode.key: 30], systemWatts: 8), apps: [xcode.key: xcode])

        #expect(profile.hours.count == 1)
        #expect(profile.apps.keys.sorted() == [xcode.key])
    }

    @Test func addsUpDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = calendar.startOfDay(for: start)
        var profile = UsageProfile()
        // Yesterday: 100 → 70 over three hours. Today: 70 → 60 over an hour.
        profile.record(level: level(100, at: midnight.addingTimeInterval(-5 * 3600)))
        profile.record(level: level(70, at: midnight.addingTimeInterval(-2 * 3600)))
        profile.record(level: level(70, pluggedIn: true, at: midnight.addingTimeInterval(-2 * 3600 + 1)))
        profile.record(level: level(70, at: midnight.addingTimeInterval(3600)))
        profile.record(level: level(60, at: midnight.addingTimeInterval(2 * 3600)))

        let days = profile.days(3, endingAt: midnight.addingTimeInterval(5 * 3600), calendar: calendar)
        #expect(days.map(\.drained) == [0, 30, 10])
        #expect(days.map(\.batterySeconds) == [0, 3 * 3600 + 1, 3600])
    }

    @Test func appEnergyOverTheProfile() {
        var profile = UsageProfile()
        profile.record(
            BatteryHistory.EnergySample(date: minutes(5), seconds: 300, joules: [xcode.key: 900, safari.key: 300], systemWatts: 10),
            apps: [xcode.key: xcode, safari.key: safari])
        let apps = profile.appEnergy(since: start)
        #expect(apps.map(\.app) == [xcode, safari])
        // 900 J at 10 W is 90 seconds of battery.
        #expect(apps.first?.batteryTime == 90)
        #expect(profile.sampledTime(since: start) == 300)
    }
}
