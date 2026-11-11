import Foundation
import Testing

@testable import BatteryKit

struct MeetingCheckTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func minutes(_ count: Double) -> Date { now.addingTimeInterval(count * 60) }
    private func onBattery(minutesLeft: Double?) -> BatterySnapshot {
        BatterySnapshot(percentage: 30, powerSource: .battery, chargeState: .discharging, timeRemaining: minutesLeft.map { $0 * 60 })
    }

    @Test func warnsWhenItRunsOutBeforeTheMeeting() throws {
        let meeting = UpcomingEvent(start: minutes(20), end: minutes(80))
        let warning = try #require(MeetingCheck.warning(snapshot: onBattery(minutesLeft: 12), events: [meeting], now: now, lead: 30 * 60))
        #expect(warning.event == meeting)
        #expect(warning.timing == .beforeStart)
        #expect(warning.runsOutAt <= minutes(12))
        #expect(warning.runsOutAt > minutes(6))
    }

    @Test func warnsWhenItRunsOutDuringTheMeeting() {
        let meeting = UpcomingEvent(start: minutes(20), end: minutes(80))
        let warning = MeetingCheck.warning(snapshot: onBattery(minutesLeft: 50), events: [meeting], now: now, lead: 30 * 60)
        #expect(warning?.timing == .duringMeeting)
    }

    @Test func staysQuietWhenTheBatteryLasts() {
        let meeting = UpcomingEvent(start: minutes(20), end: minutes(80))
        #expect(MeetingCheck.warning(snapshot: onBattery(minutesLeft: 120), events: [meeting], now: now, lead: 30 * 60) == nil)
    }

    @Test func aMarginKeepsAWarningFromFlickering() {
        let meeting = UpcomingEvent(start: minutes(20), end: minutes(80))
        // Lasts just past the end: no warning, unless one is already showing.
        let snapshot = onBattery(minutesLeft: 84)
        #expect(MeetingCheck.warning(snapshot: snapshot, events: [meeting], now: now, lead: 30 * 60) == nil)
        #expect(MeetingCheck.warning(snapshot: snapshot, events: [meeting], now: now, lead: 30 * 60, margin: 10 * 60) != nil)
    }

    @Test func waitsUntilTheMeetingIsWithinTheLeadTime() {
        let meeting = UpcomingEvent(start: minutes(90), end: minutes(120))
        let snapshot = onBattery(minutesLeft: 60)
        #expect(MeetingCheck.warning(snapshot: snapshot, events: [meeting], now: now, lead: 30 * 60) == nil)
        #expect(MeetingCheck.warning(snapshot: snapshot, events: [meeting], now: now, lead: 2 * 3600) != nil)
        #expect(MeetingCheck.nextCheck(events: [meeting], now: now, lead: 30 * 60) == minutes(60))
    }

    @Test func coversAMeetingUnderWay() {
        let meeting = UpcomingEvent(start: minutes(-10), end: minutes(50))
        let warning = MeetingCheck.warning(snapshot: onBattery(minutesLeft: 30), events: [meeting], now: now, lead: 15 * 60)
        #expect(warning?.hasStarted(now: now) == true)
        // One that's over is ignored.
        #expect(
            MeetingCheck.warning(snapshot: onBattery(minutesLeft: 5), events: [UpcomingEvent(start: minutes(-60), end: minutes(-1))], now: now, lead: 15 * 60)
                == nil)
    }

    @Test func saysNothingOnTheAdapterOrWithoutAnEstimate() {
        let meeting = UpcomingEvent(start: minutes(10), end: minutes(70))
        let pluggedIn = BatterySnapshot(percentage: 30, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 600)
        #expect(MeetingCheck.warning(snapshot: pluggedIn, events: [meeting], now: now, lead: 30 * 60) == nil)
        #expect(MeetingCheck.warning(snapshot: onBattery(minutesLeft: nil), events: [meeting], now: now, lead: 30 * 60) == nil)
    }
}

struct UsualDrainTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 14:00 on some day.
    private var now: Date { calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 800_000_000)).addingTimeInterval(14 * 3600) }
    private let xcode = BatteryHistory.AppIdentity(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
    private let safari = BatteryHistory.AppIdentity(name: "Safari", bundleIdentifier: "com.apple.Safari")

    /// `days` earlier days with an hour at 14:00 drawing `watts`, Safari using 2 W of it.
    private func profile(days: Int, watts: Double) -> UsageProfile {
        var profile = UsageProfile()
        for day in (1...days).reversed() {
            let hour = now.addingTimeInterval(-Double(day) * 24 * 3600)
            for step in 1...12 {
                let sample = BatteryHistory.EnergySample(
                    date: hour.addingTimeInterval(Double(step) * 300), seconds: 300, joules: [safari.key: 2 * 300], systemWatts: watts)
                profile.record(sample, apps: [safari.key: safari])
            }
        }
        return profile
    }

    /// The last 45 minutes drawing `watts`, with Xcode using `xcodeWatts` of it.
    private func history(watts: Double, xcodeWatts: Double) -> BatteryHistory {
        var history = BatteryHistory()
        for step in 0..<9 {
            history.record(
                joules: [xcode: xcodeWatts * 300, safari: 2 * 300], seconds: 300, systemWatts: watts,
                at: now.addingTimeInterval(-Double(8 - step) * 300))
        }
        return history
    }

    @Test func spotsMoreThanUsualAndWhy() throws {
        let drain = try #require(
            UsualDrainCheck.check(history: history(watts: 13, xcodeWatts: 3), profile: profile(days: 6, watts: 10), now: now, calendar: calendar))
        #expect(abs(drain.ratio - 1.3) < 0.001)
        #expect(drain.percentMore == 30)
        #expect(drain.cause == xcode)
    }

    @Test func noCauseWhenNoAppExplainsIt() throws {
        let drain = try #require(
            UsualDrainCheck.check(history: history(watts: 16, xcodeWatts: 0.5), profile: profile(days: 6, watts: 10), now: now, calendar: calendar))
        #expect(drain.cause == nil)
    }

    @Test func saysNothingWithoutEnoughHistory() {
        #expect(UsualDrainCheck.check(history: history(watts: 20, xcodeWatts: 8), profile: profile(days: 4, watts: 10), now: now, calendar: calendar) == nil)
    }

    @Test func saysNothingForASmallDifference() {
        #expect(UsualDrainCheck.check(history: history(watts: 11, xcodeWatts: 1), profile: profile(days: 6, watts: 10), now: now, calendar: calendar) == nil)
        // 50% more, but half a watt.
        #expect(UsualDrainCheck.check(history: history(watts: 1.5, xcodeWatts: 0.5), profile: profile(days: 6, watts: 1), now: now, calendar: calendar) == nil)
    }

    /// Waking up after a night on battery: one long sample, with a single power reading taken at wake.
    @Test func ignoresTheSampleThatSpansSleep() {
        var history = BatteryHistory()
        history.record(joules: [xcode: 3 * 8 * 3600], seconds: 8 * 3600, systemWatts: 20, at: now)
        #expect(UsualDrainCheck.check(history: history, profile: profile(days: 6, watts: 10), now: now, calendar: calendar) == nil)
    }

    @Test func saysNothingOnceTheSamplesAreOld() {
        let later = now.addingTimeInterval(30 * 60)
        #expect(UsualDrainCheck.check(history: history(watts: 20, xcodeWatts: 8), profile: profile(days: 6, watts: 10), now: later, calendar: calendar) == nil)
    }

    @Test func wordsLargeDifferencesAsTimes() {
        let drain = UnusualDrain(currentWatts: 31, usualWatts: 10, cause: nil)
        #expect(drain.percentMore == nil)
        #expect(drain.timesAsMuch == 3)
        #expect(UnusualDrain(currentWatts: 12.2, usualWatts: 10, cause: nil).percentMore == 20)
    }
}

struct NewAppCheckTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let figma = BatteryHistory.AppIdentity(name: "Figma", bundleIdentifier: "com.figma.Desktop")
    private let safari = BatteryHistory.AppIdentity(name: "Safari", bundleIdentifier: "com.apple.Safari")

    private func days(_ count: Double) -> TimeInterval { count * 24 * 3600 }

    /// Safari every day for `historyDays`, then Figma joining in the last day, drawing `figmaWatts`.
    private func setUp(historyDays: Int, figmaWatts: Double) -> (BatteryHistory, UsageProfile) {
        var history = BatteryHistory()
        var profile = UsageProfile()
        for day in (0..<historyDays).reversed() {
            for step in 1...12 {
                let date = now.addingTimeInterval(-days(Double(day)) - Double(13 - step) * 300 - 3600)
                var joules = [safari: 2.0 * 300]
                if day == 0 { joules[figma] = figmaWatts * 300 }
                history.record(joules: joules, seconds: 300, systemWatts: 10, at: date)
                if let sample = history.samples.last { profile.record(sample, apps: history.apps) }
            }
        }
        return (history, profile)
    }

    @Test func spotsANewHungryApp() {
        let (history, profile) = setUp(historyDays: 8, figmaWatts: 4)
        #expect(NewAppCheck.newApps(history: history, profile: profile, now: now).map(\.app) == [figma])
    }

    @Test func notWhileTheHistoryIsYoung() {
        let (history, profile) = setUp(historyDays: 3, figmaWatts: 4)
        #expect(NewAppCheck.newApps(history: history, profile: profile, now: now).isEmpty)
    }

    @Test func notWhenItBarelyUsesAnything() {
        let (history, profile) = setUp(historyDays: 8, figmaWatts: 0.2)
        #expect(NewAppCheck.newApps(history: history, profile: profile, now: now).isEmpty)
    }

    @Test func notAnAppThatWasAroundBefore() {
        let (history, profile) = setUp(historyDays: 8, figmaWatts: 4)
        // Figma was first seen ten days ago, so it isn't new, however hungry it is today.
        var apps = profile.apps
        apps[figma.key]?.firstSeen = now.addingTimeInterval(-days(10))
        let seenBefore = UsageProfile(hours: profile.hours, apps: apps, lastLevel: nil, now: now)
        #expect(NewAppCheck.newApps(history: history, profile: seenBefore, now: now).isEmpty)
    }
}
