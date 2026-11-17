import Foundation
import Testing

@testable import BatteryKit

struct UsageReportTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Midnight on a Monday, in Copenhagen.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))! }
    private let xcode = BatteryHistory.AppIdentity(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
    private let safari = BatteryHistory.AppIdentity(name: "Safari", bundleIdentifier: "com.apple.Safari")
    private var apps: [String: BatteryHistory.AppIdentity] { [xcode.key: xcode, safari.key: safari] }

    private func at(day: Int, hour: Double) -> Date { monday.addingTimeInterval(Double(day) * 24 * 3600 + hour * 3600) }

    /// An hour on battery from `hour`, using `drained` points, with the apps sampled over all of it.
    private func useHour(
        _ profile: inout UsageProfile, day: Int, hour: Double, drained: Int, joules: [String: Double], watts: Double = 10
    ) {
        let start = at(day: day, hour: hour)
        profile.record(level: .init(date: start, percentage: 80, isPluggedIn: false))
        profile.record(level: .init(date: start.addingTimeInterval(3599), percentage: 80 - drained, isPluggedIn: false))
        profile.record(level: .init(date: start.addingTimeInterval(3600), percentage: 80 - drained, isPluggedIn: true))
        // Samples every five minutes, as the app takes them, so each has a power reading.
        for step in 1...12 {
            profile.record(
                BatteryHistory.EnergySample(
                    date: start.addingTimeInterval(Double(step) * 300), seconds: 300, joules: joules.mapValues { $0 / 12 }, systemWatts: watts),
                apps: apps)
        }
    }

    @Test func cutsTheTimeIntoDaysAndRanksTheApps() {
        var profile = UsageProfile(hours: [], apps: [:], lastLevel: nil, now: at(day: 7, hour: 0), retention: 365 * 24 * 3600)
        useHour(&profile, day: 0, hour: 9, drained: 10, joules: [xcode.key: 3000, safari.key: 1000])
        useHour(&profile, day: 2, hour: 14, drained: 6, joules: [xcode.key: 1000])
        useHour(&profile, day: 2, hour: 16, drained: 4, joules: [safari.key: 1000])

        let report = profile.report(from: monday, to: at(day: 7, hour: 0), granularity: .day, calendar: calendar)
        #expect(report.periods.count == 7)
        #expect(report.periods.map(\.drained) == [10, 0, 10, 0, 0, 0, 0])
        #expect(report.periods[0].batterySeconds == 3600)
        #expect(report.drained == 20)
        #expect(report.apps.map(\.app) == [xcode, safari])
        #expect(report.apps[0].joules == 4000)
        #expect(report.apps[0].share == 4000.0 / 6000)
        #expect(report.apps.map(\.activeDays) == [2, 2])
        // 10 W the whole time: 4000 J is 400 seconds of battery.
        #expect(report.apps[0].batteryTime == 400)
        #expect(report.averageDay == UsageReport.AverageDay(batterySeconds: 5400, drained: 10, days: 2))
    }

    @Test func aWeekStartsOnTheCalendarsFirstDay() {
        let periods = UsageProfile.periods(from: at(day: 3, hour: 12), to: at(day: 20, hour: 0), granularity: .week, calendar: calendar)
        #expect(periods.first?.start == monday)
        #expect(periods.count == 3)
        #expect(periods.last?.end == at(day: 20, hour: 0))
    }

    @Test func daysFollowTheCalendarAcrossTheClockChange() {
        // Copenhagen's clocks go back on 25 October 2026, so that day is 25 hours long.
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        let periods = UsageProfile.periods(from: start, to: start.addingTimeInterval(3 * 24 * 3600), granularity: .day, calendar: calendar)
        #expect(periods.map { $0.end.timeIntervalSince($0.start) / 3600 }.prefix(2) == [24, 25])
    }

    @Test func anAppsOwnReportHasItsDaysAndHours() {
        var profile = UsageProfile(hours: [], apps: [:], lastLevel: nil, now: at(day: 7, hour: 0), retention: 365 * 24 * 3600)
        for day in 0..<5 {
            useHour(&profile, day: day, hour: 9, drained: 5, joules: [xcode.key: 360, safari.key: 360])
            useHour(&profile, day: day, hour: 14, drained: 8, joules: [xcode.key: 3600, safari.key: 360])
            useHour(&profile, day: day, hour: 20, drained: 3, joules: [xcode.key: 360])
        }
        let report = profile.appReport(for: xcode.key, from: monday, to: at(day: 7, hour: 0), granularity: .day, calendar: calendar)
        #expect(report?.rank == 1)
        #expect(report?.appCount == 2)
        #expect(report?.activeDays == 5)
        #expect(report?.dayCount == 7)
        #expect(report?.periods.map(\.joules) == [4320, 4320, 4320, 4320, 4320, 0, 0])
        #expect(report?.hoursOfDay.count == 24)
        #expect(report?.hoursOfDay[14].watts == 1)
        #expect(report?.hoursOfDay[9].watts == 0.1)
        #expect(report?.hoursOfDay[3].watts == nil)
        #expect(report?.busiestHour == 14)
        // Nothing before to compare with.
        #expect(report?.change == nil)
        #expect(profile.appReport(for: "com.example.unknown", from: monday, to: at(day: 7, hour: 0), granularity: .day) == nil)
    }

    @Test func comparesWithTheSameLengthOfTimeBefore() {
        var profile = UsageProfile(hours: [], apps: [:], lastLevel: nil, now: at(day: 14, hour: 0), retention: 365 * 24 * 3600)
        for day in 0..<7 {
            useHour(&profile, day: day, hour: 10, drained: 5, joules: [xcode.key: 1000])
            useHour(&profile, day: day, hour: 15, drained: 5, joules: [xcode.key: 1000])
        }
        for day in 7..<14 {
            useHour(&profile, day: day, hour: 10, drained: 5, joules: [xcode.key: 1500])
            useHour(&profile, day: day, hour: 15, drained: 5, joules: [xcode.key: 1500])
        }
        let report = profile.appReport(for: xcode.key, from: at(day: 7, hour: 0), to: at(day: 14, hour: 0), granularity: .day, calendar: calendar)
        #expect(abs((report?.change ?? 0) - 0.5) < 0.0001)
        // Evenly spread, no hour stands out.
        #expect(report?.busiestHour == nil)
    }

    @Test func anHourOfTheDayMeasuredForMinutesHasNoDraw() {
        var profile = UsageProfile()
        let start = at(day: 0, hour: 9)
        profile.record(
            BatteryHistory.EnergySample(date: start.addingTimeInterval(5 * 60), seconds: 5 * 60, joules: [xcode.key: 300], systemWatts: 8), apps: apps)
        let report = profile.appReport(for: xcode.key, from: monday, to: at(day: 1, hour: 0), granularity: .hour, calendar: calendar)
        #expect(report?.periods.count == 24)
        #expect(report?.periods[9].joules == 300)
        #expect(report?.hoursOfDay[9].watts == nil)
        #expect(report?.averageWatts == 1)
    }

    @Test func anEmptyHistoryMakesAnEmptyReport() {
        let report = UsageProfile().report(from: monday, to: at(day: 30, hour: 0), granularity: .day, calendar: calendar)
        #expect(report.isEmpty)
        #expect(report.apps.isEmpty)
        #expect(report.periods.count == 30)
        #expect(report.averageDay == nil)
        #expect(UsageProfile().report(from: monday, to: monday, granularity: .day).periods.isEmpty)
    }

    @Test func exportsARowForEachAppEachDay() {
        var profile = UsageProfile(hours: [], apps: [:], lastLevel: nil, now: at(day: 7, hour: 0), retention: 365 * 24 * 3600)
        useHour(&profile, day: 0, hour: 9, drained: 10, joules: [xcode.key: 3600, safari.key: 1800])
        useHour(&profile, day: 2, hour: 14, drained: 6, joules: [safari.key: 7200])
        let lines = HistoryExport.appsCSV(profile: profile, calendar: calendar).split(separator: "\n")
        #expect(lines.count == 4)
        #expect(lines[0] == "day,app,bundle_identifier,energy_wh,share_percent,battery_minutes")
        #expect(lines[1] == "2026-11-02,Xcode,com.apple.dt.Xcode,1.000,66.7,6.0")
        #expect(lines[2] == "2026-11-02,Safari,com.apple.Safari,0.500,33.3,3.0")
        #expect(lines[3] == "2026-11-04,Safari,com.apple.Safari,2.000,100.0,12.0")
        #expect(HistoryExport.suggestedFileName(.appsCSV, now: monday).hasSuffix(".csv"))
    }
}
