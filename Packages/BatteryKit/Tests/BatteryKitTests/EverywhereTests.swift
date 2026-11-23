import Foundation
import Testing

@testable import BatteryKit

// 0.5.0: the forecast, the weekly summary, rules, and what the widgets are handed.

private let copenhagen: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
    calendar.firstWeekday = 2
    return calendar
}()

/// Midnight on Monday 2 November 2026, in Copenhagen.
private let monday = copenhagen.date(from: DateComponents(year: 2026, month: 11, day: 2))!
private func at(day: Int, hour: Double) -> Date { monday.addingTimeInterval(Double(day) * 24 * 3600 + hour * 3600) }

private let xcode = BatteryHistory.AppIdentity(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
private let safari = BatteryHistory.AppIdentity(name: "Safari", bundleIdentifier: "com.apple.Safari")
private let figma = BatteryHistory.AppIdentity(name: "Figma", bundleIdentifier: "com.figma.Desktop")
private let knownApps = [xcode.key: xcode, safari.key: safari, figma.key: figma]

/// An hour on battery from `hour`, using `drained` points, with the apps sampled over all of it.
private func useHour(_ profile: inout UsageProfile, day: Int, hour: Double, drained: Int, joules: [String: Double] = [:], watts: Double = 10) {
    let start = at(day: day, hour: hour)
    profile.record(level: .init(date: start, percentage: 80, isPluggedIn: false))
    profile.record(level: .init(date: start.addingTimeInterval(3599), percentage: 80 - drained, isPluggedIn: false))
    profile.record(level: .init(date: start.addingTimeInterval(3600), percentage: 80 - drained, isPluggedIn: true))
    for step in 1...12 {
        profile.record(
            BatteryHistory.EnergySample(
                date: start.addingTimeInterval(Double(step) * 300), seconds: 300, joules: joules.mapValues { $0 / 12 }, systemWatts: watts),
            apps: knownApps)
    }
}

private func emptyProfile(now: Date) -> UsageProfile {
    UsageProfile(hours: [], apps: [:], lastLevel: nil, now: now, retention: 365 * 24 * 3600)
}

private func onBattery(_ percentage: Int, minutesLeft: Double?) -> BatterySnapshot {
    BatterySnapshot(percentage: percentage, powerSource: .battery, chargeState: .discharging, timeRemaining: minutesLeft.map { $0 * 60 })
}

// MARK: - Forecast

struct BatteryForecastTests {
    @Test func followsTheCurrentPaceWithoutHistory() throws {
        let now = at(day: 10, hour: 9)
        // 50% with 5 hours left: 10 points an hour.
        let forecast = try #require(
            ForecastModel.forecast(
                snapshot: onBattery(50, minutesLeft: 300), profile: emptyProfile(now: now), history: BatteryHistory(), now: now, calendar: copenhagen))
        #expect(forecast.basis == .currentPace)
        let low = try #require(forecast.reachesLow)
        let out = try #require(forecast.runsOut)
        // 30 points to 20%: about three hours; 50 to empty: about five.
        #expect(abs(low.timeIntervalSince(now) - 3 * 3600) <= 10 * 60)
        #expect(abs(out.timeIntervalSince(now) - 5 * 3600) <= 10 * 60)
        #expect(forecast.points.first?.percentage == 50)
        #expect(forecast.points.last?.percentage == 0)
        // Points step down, never up.
        for (a, b) in zip(forecast.points, forecast.points.dropFirst()) { #expect(b.percentage <= a.percentage) }
    }

    @Test func leansTowardsTheUsualPaceForTheHoursAhead() throws {
        let now = at(day: 10, hour: 9)
        var profile = emptyProfile(now: now)
        // Every afternoon of the week before, 25 points an hour from 10:00 on; mornings, 5.
        for day in 3..<10 {
            useHour(&profile, day: day, hour: 9, drained: 5)
            for hour in 10..<16 { useHour(&profile, day: day, hour: Double(hour), drained: 25) }
        }
        let snapshot = onBattery(90, minutesLeft: 18 * 60)  // 5 points an hour right now
        let usual = try #require(ForecastModel.forecast(snapshot: snapshot, profile: profile, history: BatteryHistory(), now: now, calendar: copenhagen))
        let plain = try #require(
            ForecastModel.forecast(snapshot: snapshot, profile: emptyProfile(now: now), history: BatteryHistory(), now: now, calendar: copenhagen))
        #expect(usual.basis == .usualDay)
        // The busy afternoon brings the low level within the day; at the current pace alone, it's past the horizon.
        let usualLow = try #require(usual.reachesLow)
        #expect(plain.reachesLow == nil)
        #expect(usualLow > now.addingTimeInterval(2 * 3600))
        #expect(usualLow < now.addingTimeInterval(6 * 3600))
    }

    @Test func usesTheLevelsFallWhileMacOSIsStillCalculating() throws {
        let now = at(day: 10, hour: 9)
        var history = BatteryHistory()
        history.record(
            BatterySnapshot(percentage: 60, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: nil), at: now.addingTimeInterval(-50 * 60))
        history.record(onBattery(60, minutesLeft: nil), at: now.addingTimeInterval(-45 * 60))
        history.record(onBattery(54, minutesLeft: nil), at: now.addingTimeInterval(-5 * 60))
        let forecast = try #require(
            ForecastModel.forecast(
                snapshot: onBattery(54, minutesLeft: nil), profile: emptyProfile(now: now), history: history, now: now, calendar: copenhagen))
        // 6 points in 45 minutes: 8 an hour, so 34 points to 20% in about four and a quarter hours.
        let low = try #require(forecast.reachesLow)
        #expect(abs(low.timeIntervalSince(now) - 4.25 * 3600) <= 15 * 60)
    }

    @Test func saysNothingOnTheAdapterOrWithoutAPace() {
        let now = at(day: 10, hour: 9)
        let charging = BatterySnapshot(percentage: 50, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600)
        #expect(ForecastModel.forecast(snapshot: charging, profile: emptyProfile(now: now), history: BatteryHistory(), now: now) == nil)
        #expect(ForecastModel.forecast(snapshot: onBattery(50, minutesLeft: nil), profile: emptyProfile(now: now), history: BatteryHistory(), now: now) == nil)
    }

    @Test func stopsAtTheHorizon() throws {
        let now = at(day: 10, hour: 9)
        // 100% with 40 hours left: nowhere near empty in twelve hours.
        let forecast = try #require(
            ForecastModel.forecast(
                snapshot: onBattery(100, minutesLeft: 40 * 60), profile: emptyProfile(now: now), history: BatteryHistory(), now: now, calendar: copenhagen))
        #expect(forecast.runsOut == nil)
        #expect(forecast.reachesLow == nil)
        let last = try #require(forecast.points.last)
        #expect(last.date.timeIntervalSince(now) <= BatteryForecast.horizon)
        #expect(last.date.timeIntervalSince(now) >= BatteryForecast.horizon - BatteryForecast.step)
    }

    @Test func alreadyLowHasNoLowTimeButStillRunsOut() throws {
        let now = at(day: 10, hour: 9)
        let forecast = try #require(
            ForecastModel.forecast(
                snapshot: onBattery(15, minutesLeft: 90), profile: emptyProfile(now: now), history: BatteryHistory(), now: now, calendar: copenhagen))
        #expect(forecast.reachesLow == nil)
        #expect(forecast.runsOut != nil)
    }

    @Test func widgetForecastInterpolates() {
        let start = at(day: 0, hour: 9)
        let forecast = WidgetState.Forecast(
            points: [.init(date: start, percentage: 50), .init(date: start.addingTimeInterval(3600), percentage: 40)], reachesLow: nil, runsOut: nil,
            lowLevel: 20)
        #expect(forecast.percentage(at: start.addingTimeInterval(1800)) == 45)
        #expect(forecast.percentage(at: start.addingTimeInterval(7200)) == nil)
    }
}

// MARK: - Weekly summary

struct WeeklySummaryTests {
    @Test func comparesAWeekWithTheOneBefore() throws {
        let now = at(day: 14, hour: 9)  // the Monday after
        var profile = emptyProfile(now: now)
        // The week before last: two hours a day, Monday to Friday.
        for day in 0..<5 {
            useHour(&profile, day: day, hour: 10, drained: 10, joules: [safari.key: 3000])
            useHour(&profile, day: day, hour: 11, drained: 10, joules: [safari.key: 3000])
        }
        // Last week: three hours a day, and Figma joins in big.
        for day in 7..<12 {
            for hour in 10..<13 { useHour(&profile, day: day, hour: Double(hour), drained: 10, joules: [safari.key: 3000, figma.key: 6000]) }
        }
        let summary = try #require(profile.lastWeekSummary(now: now, calendar: copenhagen))
        #expect(summary.interval.start == at(day: 7, hour: 0))
        #expect(!summary.isUnderWay)
        #expect(summary.totals.drained == 150)
        #expect(summary.previous?.drained == 100)
        #expect(abs((summary.batteryTimeChange ?? 0) - 0.5) < 0.02)
        #expect(abs((summary.drainedChange ?? 0) - 0.5) < 0.001)
        #expect(summary.topApps.first?.app == figma)
        #expect(summary.biggestRise?.app == figma)
        #expect(summary.biggestRise?.previousJoules == 0)
        #expect(summary.busiestDay?.drained == 30)
        #expect(summary.totals.charges == 1.5)
    }

    @Test func aWeekUnderWayIsComparedWithTheSameDays() throws {
        var profile = emptyProfile(now: at(day: 9, hour: 12))
        for day in 0..<7 { useHour(&profile, day: day, hour: 10, drained: 10) }
        useHour(&profile, day: 7, hour: 10, drained: 12)
        useHour(&profile, day: 8, hour: 10, drained: 12)
        // Wednesday noon: Monday and Tuesday so far, against last Monday to Wednesday noon.
        let summary = try #require(profile.weeklySummary(forWeekContaining: at(day: 9, hour: 12), now: at(day: 9, hour: 12), calendar: copenhagen))
        #expect(summary.isUnderWay)
        #expect(summary.totals.drained == 24)
        #expect(summary.previous?.drained == 30)
    }

    @Test func noWeekBeforeMeansNoComparison() throws {
        let now = at(day: 7, hour: 9)
        var profile = emptyProfile(now: now)
        useHour(&profile, day: 3, hour: 10, drained: 10, joules: [xcode.key: 9000])
        let summary = try #require(profile.lastWeekSummary(now: now, calendar: copenhagen))
        #expect(summary.previous == nil)
        #expect(summary.batteryTimeChange == nil)
        #expect(summary.biggestRise == nil)
        #expect(!summary.isEmpty)
        #expect(UsageProfile().lastWeekSummary(now: now, calendar: copenhagen)?.isEmpty == true)
    }
}

// MARK: - Rules

struct RuleEngineTests {
    private let low = BatteryRule(trigger: .dropsTo(20), actions: [.lowPowerMode(true)])
    private let charged = BatteryRule(trigger: .chargesTo(80), actions: [.notify])
    private let plug = BatteryRule(trigger: .pluggedIn, actions: [.lowPowerMode(false)])
    private let unplug = BatteryRule(trigger: .unplugged, actions: [.runShortcut("Unplugged")])

    private func battery(_ percentage: Int) -> BatterySnapshot { onBattery(percentage, minutesLeft: 120) }
    private func adapter(_ percentage: Int) -> BatterySnapshot {
        BatterySnapshot(percentage: percentage, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600)
    }

    @Test func aLevelRuleRunsOnceOnTheWayDown() {
        var engine = RuleEngine()
        let rules = [low]
        let start = at(day: 0, hour: 9)
        #expect(engine.update(with: battery(22), rules: rules, at: start).isEmpty)
        #expect(engine.update(with: battery(21), rules: rules, at: start).isEmpty)
        #expect(engine.update(with: battery(20), rules: rules, at: start) == [low])
        #expect(engine.update(with: battery(19), rules: rules, at: start).isEmpty)
        // Wobbling back to 21% doesn't set it off again…
        #expect(engine.update(with: battery(21), rules: rules, at: start).isEmpty)
        #expect(engine.update(with: battery(20), rules: rules, at: start).isEmpty)
        // …charging past 23% does.
        _ = engine.update(with: adapter(40), rules: rules, at: start)
        _ = engine.update(with: battery(40), rules: rules, at: start.addingTimeInterval(60))
        #expect(engine.update(with: battery(20), rules: rules, at: start.addingTimeInterval(120)) == [low])
    }

    @Test func nothingRunsForWhereTheBatteryAlreadyWas() {
        var engine = RuleEngine()
        // Opened at 15%: the 20% rule waits for the next time down.
        #expect(engine.update(with: battery(15), rules: [low], at: at(day: 0, hour: 9)).isEmpty)
        #expect(engine.update(with: battery(14), rules: [low], at: at(day: 0, hour: 9)).isEmpty)
        // A rule made below its level waits too.
        var made = RuleEngine()
        _ = made.update(with: battery(15), rules: [], at: at(day: 0, hour: 9))
        made.didChange(low)
        #expect(made.update(with: battery(14), rules: [low], at: at(day: 0, hour: 9)).isEmpty)
    }

    @Test func chargerRulesRunOnTheChangeAndIgnoreALooseCable() {
        var engine = RuleEngine()
        let rules = [plug, unplug]
        let start = at(day: 0, hour: 9)
        _ = engine.update(with: battery(50), rules: rules, at: start)
        #expect(engine.update(with: adapter(50), rules: rules, at: start.addingTimeInterval(60)) == [plug])
        // Out and back in within a couple of seconds: a loose cable.
        #expect(engine.update(with: battery(50), rules: rules, at: start.addingTimeInterval(62)).isEmpty)
        #expect(engine.update(with: adapter(50), rules: rules, at: start.addingTimeInterval(63)).isEmpty)
        #expect(engine.update(with: battery(50), rules: rules, at: start.addingTimeInterval(600)) == [unplug])
    }

    @Test func aChargeRuleRunsOnTheWayUp() {
        var engine = RuleEngine()
        let start = at(day: 0, hour: 9)
        _ = engine.update(with: adapter(70), rules: [charged], at: start)
        #expect(engine.update(with: adapter(79), rules: [charged], at: start).isEmpty)
        #expect(engine.update(with: adapter(80), rules: [charged], at: start) == [charged])
        #expect(engine.update(with: adapter(81), rules: [charged], at: start).isEmpty)
    }

    @Test func turnedOffRulesDontRun() {
        var engine = RuleEngine()
        var off = low
        off.isEnabled = false
        _ = engine.update(with: battery(25), rules: [off], at: at(day: 0, hour: 9))
        #expect(engine.update(with: battery(20), rules: [off], at: at(day: 0, hour: 9)).isEmpty)
    }

    @Test func rulesSurviveBeingSaved() {
        let rules = [low, charged, plug, unplug, BatteryRule(trigger: .dropsTo(10), actions: [.quitApps(["com.figma.Desktop"]), .chargeLimit(80)])]
        #expect(BatteryRule.decode(BatteryRule.encode(rules)) == rules)
        #expect(BatteryRule.decode(Data("nonsense".utf8)).isEmpty)
        #expect(BatteryRule.decode(nil).isEmpty)
    }
}

// MARK: - Widget state

struct WidgetStateTests {
    private func state(percentage: Int = 50, minutesLeft: Double? = 120, apps: [String] = ["a"]) -> WidgetState {
        WidgetState(
            updatedAt: at(day: 0, hour: 9),
            battery: .init(
                percentage: percentage, isPluggedIn: false, isCharging: false, isLowPowerModeOn: false, timeRemaining: minutesLeft.map { $0 * 60 },
                chargeTarget: 100),
            apps: apps.map { .init(key: $0, name: $0, bundleIdentifier: nil, share: 0.5, batteryTime: nil, iconFile: nil) })
    }

    @Test func roundTrips() throws {
        let original = state()
        #expect(WidgetState.decode(try original.encoded()) == original)
    }

    @Test func onlyVisibleChangesCount() {
        #expect(state().differsVisibly(from: nil))
        #expect(!state().differsVisibly(from: state()))
        #expect(!state(minutesLeft: 121).differsVisibly(from: state(minutesLeft: 125)))
        #expect(state(minutesLeft: 100).differsVisibly(from: state(minutesLeft: 125)))
        #expect(state(percentage: 49).differsVisibly(from: state()))
        #expect(state(apps: ["b"]).differsVisibly(from: state()))
    }
}
