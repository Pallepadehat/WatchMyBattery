import Foundation

/// The history over a stretch of time, for looking back: what each day (or hour, or week) used, and every app that
/// used the battery, with its share. Worked out from the hourly summaries (``UsageProfile``), so it reaches as far
/// back as they're kept: two weeks, or up to a year if Settings keeps them longer.
///
/// Like the rest of the history, it counts time on battery only: apps are measured then, and not while plugged in.
public struct UsageReport: Sendable, Equatable {
    /// How finely the time is cut up: an hour for the last day, days for weeks and months, weeks for a year.
    public enum Granularity: Sendable, Equatable {
        case hour
        case day
        case week
    }

    /// One slice of the report's time: an hour, a day or a week.
    public struct Period: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        /// Time on battery, including time asleep.
        public var batterySeconds: Double = 0
        /// Percentage points used on battery.
        public var drained: Int = 0
        /// How much of it the energy samples cover.
        public var sampledSeconds: Double = 0
        /// What every app together used, in joules.
        public var appJoules: Double = 0

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }

        public var id: Date { start }
        public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
    }

    /// An app's part of the report.
    public struct App: Sendable, Equatable, Identifiable {
        public let app: BatteryHistory.AppIdentity
        public let joules: Double
        /// The battery time this energy is worth at the Mac's average power draw; `nil` without power readings.
        public let batteryTime: TimeInterval?
        /// Its share of what all the apps used, 0–1.
        public let share: Double
        /// The days (by the calendar) it used any energy on.
        public let activeDays: Int
        /// When it was last among the apps using the most, however long ago.
        public let lastSeen: Date?

        public var id: String { app.key }
    }

    public let granularity: Granularity
    /// In date order, with no gaps: a period with nothing in it is there, empty.
    public let periods: [Period]
    /// Every app that used energy, most first.
    public let apps: [App]
    /// The Mac's average power draw on battery while measured; `nil` without power readings.
    public let averageWatts: Double?

    public var start: Date { periods.first?.start ?? .distantPast }
    public var end: Date { periods.last?.end ?? .distantPast }
    public var batterySeconds: Double { periods.reduce(0) { $0 + $1.batterySeconds } }
    public var drained: Int { periods.reduce(0) { $0 + $1.drained } }
    public var sampledSeconds: Double { periods.reduce(0) { $0 + $1.sampledSeconds } }
    public var appJoules: Double { apps.reduce(0) { $0 + $1.joules } }

    /// Nothing at all happened on battery in it.
    public var isEmpty: Bool { periods.allSatisfy { $0.batterySeconds == 0 && $0.sampledSeconds == 0 } }

    /// An average day on battery, over the days that had any (a few minutes don't make a day).
    public struct AverageDay: Sendable, Equatable {
        public let batterySeconds: Double
        /// Percentage points.
        public let drained: Double
        /// How many days it's the average of.
        public let days: Int
    }

    /// Over the days with time on battery (a few minutes don't make a day), whether the report is cut into days or
    /// not; `nil` without any.
    public let averageDay: AverageDay?

    static func averageDay(seconds: [Double], drained: [Int]) -> AverageDay? {
        let used = seconds.indices.filter { drained[$0] > 0 || seconds[$0] >= 60 }
        guard !used.isEmpty else { return nil }
        return AverageDay(
            batterySeconds: used.reduce(0) { $0 + seconds[$1] } / Double(used.count),
            drained: Double(used.reduce(0) { $0 + drained[$1] }) / Double(used.count), days: used.count)
    }

    /// The app with this key, if it used anything.
    public func app(_ key: String) -> App? { apps.first { $0.app.key == key } }

    /// Its place among the apps, from 1.
    public func rank(of key: String) -> Int? { apps.firstIndex { $0.app.key == key }.map { $0 + 1 } }
}

/// One app over a stretch of time, for a closer look: how much it used and when, by the period and by the hour of
/// the day, and whether it's using more or less than before.
public struct AppUsageReport: Sendable, Equatable {
    /// The app's use in one of the report's periods.
    public struct Period: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        public let joules: Double
        /// At the report's average power draw, like ``UsageReport/App/batteryTime``.
        public let batteryTime: TimeInterval?

        public var id: Date { start }
    }

    /// An hour of the day (0–23), over every day in the report.
    public struct HourOfDay: Sendable, Equatable, Identifiable {
        public let hour: Int
        /// The app's average power draw while measured in this hour of the day; `nil` when it was hardly measured
        /// then, as a few minutes say little.
        public let watts: Double?
        /// How long, over all the days, this hour was measured.
        public let sampledSeconds: Double

        public var id: Int { hour }
    }

    public let app: BatteryHistory.AppIdentity
    public let granularity: UsageReport.Granularity
    public let joules: Double
    public let batteryTime: TimeInterval?
    /// Its share of what all the apps used, 0–1.
    public let share: Double
    /// Its place among the apps, from 1; `nil` when it used nothing in the report's time.
    public let rank: Int?
    /// Of how many apps.
    public let appCount: Int
    public let activeDays: Int
    /// Days in the report, to say "on 12 of 30 days".
    public let dayCount: Int
    /// Its average power draw over all the time on battery measured, whether it was running or not: what it costs
    /// the battery on a typical stretch, comparable from one report to the next.
    public let averageWatts: Double?
    public let periods: [Period]
    /// All 24, from midnight.
    public let hoursOfDay: [HourOfDay]
    /// The hour of the day it uses the most, when that's clear: measured long enough, and well above the others.
    public let busiestHour: Int?
    public let firstSeen: Date?
    public let lastSeen: Date?
    /// Its average power draw against the same length of time just before, as a fraction (0.25 is a quarter more);
    /// `nil` when either has too little measured to compare.
    public let change: Double?

    /// An hour of the day needs this much measuring, over all the days, before its draw is shown.
    public static let minimumHourSampling: TimeInterval = 10 * 60
    /// Comparing with before needs this much measuring on each side.
    public static let minimumComparedSampling: TimeInterval = 2 * 3600
}

extension UsageProfile {
    /// The history from `start` to `end`, cut into hours, days or weeks by `calendar`. The first period starts at the
    /// beginning of the hour, day or week `start` falls in.
    public func report(
        from start: Date, to end: Date, granularity: UsageReport.Granularity, calendar: Calendar = .current
    ) -> UsageReport {
        var periods = Self.periods(from: start, to: end, granularity: granularity, calendar: calendar)
        guard let first = periods.first?.start else {
            return UsageReport(granularity: granularity, periods: [], apps: [], averageWatts: nil, averageDay: nil)
        }

        // Each app gets a slot the first time it shows up, so the thousands of entries a year of hours holds cost
        // one dictionary lookup each rather than several.
        var slots: [String: Int] = [:]
        var keys: [String] = []
        var totals: [Double] = []
        var activeDays: [Int] = []
        var lastActiveDay: [Int] = []
        var systemJoules = 0.0
        var measured = 0.0
        var index = 0
        var day = -1
        var dayEnd = Date.distantPast
        var daySeconds: [Double] = []
        var dayDrained: [Int] = []
        for hour in hours(since: first) where hour.start >= first && hour.start < end {
            while index + 1 < periods.count, hour.start >= periods[index + 1].start { index += 1 }
            periods[index].batterySeconds += hour.batterySeconds
            periods[index].drained += hour.drained
            periods[index].sampledSeconds += hour.sampledSeconds
            systemJoules += hour.systemJoules
            measured += hour.measuredSeconds
            // Hours come in order, so a day only has to be worked out when one ends.
            if hour.start >= dayEnd {
                day += 1
                let dayStart = calendar.startOfDay(for: hour.start)
                dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
                daySeconds.append(0)
                dayDrained.append(0)
            }
            daySeconds[day] += hour.batterySeconds
            dayDrained[day] += hour.drained
            var hourTotal = 0.0
            for (key, joules) in hour.appJoules where joules > 0 {
                hourTotal += joules
                let slot: Int
                if let known = slots[key] {
                    slot = known
                } else {
                    slot = keys.count
                    slots[key] = slot
                    keys.append(key)
                    totals.append(0)
                    activeDays.append(0)
                    lastActiveDay.append(-1)
                }
                totals[slot] += joules
                if lastActiveDay[slot] != day {
                    lastActiveDay[slot] = day
                    activeDays[slot] += 1
                }
            }
            periods[index].appJoules += hourTotal
        }
        let averageWatts = measured > 0 ? systemJoules / measured : nil
        let all = totals.reduce(0, +)
        let ranked = keys.indices
            .compactMap { slot -> UsageReport.App? in
                guard let app = apps[keys[slot]] else { return nil }
                let joules = totals[slot]
                return UsageReport.App(
                    app: app.identity, joules: joules, batteryTime: averageWatts.map { joules / $0 }, share: all > 0 ? joules / all : 0,
                    activeDays: activeDays[slot], lastSeen: app.lastSeen)
            }
            .sorted { $0.joules != $1.joules ? $0.joules > $1.joules : $0.id < $1.id }
        return UsageReport(
            granularity: granularity, periods: periods, apps: ranked, averageWatts: averageWatts,
            averageDay: UsageReport.averageDay(seconds: daySeconds, drained: dayDrained))
    }

    /// One app from `start` to `end`, as ``report(from:to:granularity:calendar:)`` cuts the time up. `nil` for an app
    /// the history doesn't know (any more).
    public func appReport(
        for key: String, from start: Date, to end: Date, granularity: UsageReport.Granularity, calendar: Calendar = .current
    ) -> AppUsageReport? {
        guard let known = apps[key] else { return nil }
        let report = report(from: start, to: end, granularity: granularity, calendar: calendar)
        let entry = report.app(key)
        let first = report.start

        var joules = [Double](repeating: 0, count: report.periods.count)
        var hourJoules = [Double](repeating: 0, count: 24)
        var hourSampled = [Double](repeating: 0, count: 24)
        var index = 0
        for hour in hours(since: first) where hour.start >= first && hour.start < end {
            while index + 1 < report.periods.count, hour.start >= report.periods[index + 1].start { index += 1 }
            let used = hour.appJoules[key] ?? 0
            joules[index] += used
            // Only the measured part of the hour says anything about when the app uses power.
            guard hour.sampledSeconds > 0 else { continue }
            let clock = calendar.component(.hour, from: hour.start)
            hourJoules[clock] += used
            hourSampled[clock] += hour.sampledSeconds
        }

        let hoursOfDay = (0..<24).map { clock in
            AppUsageReport.HourOfDay(
                hour: clock,
                watts: hourSampled[clock] >= AppUsageReport.minimumHourSampling ? hourJoules[clock] / hourSampled[clock] : nil,
                sampledSeconds: hourSampled[clock])
        }
        let sampled = report.sampledSeconds
        let total = entry?.joules ?? 0
        let averageWatts = sampled > 0 ? total / sampled : nil

        // Against the same length of time just before, measured the same way.
        var change: Double?
        let length = report.end.timeIntervalSince(report.start)
        if length > 0, sampled >= AppUsageReport.minimumComparedSampling, let averageWatts {
            let before = self.report(from: report.start.addingTimeInterval(-length), to: report.start, granularity: granularity, calendar: calendar)
            let beforeSampled = before.sampledSeconds
            if beforeSampled >= AppUsageReport.minimumComparedSampling, let earlier = before.app(key), earlier.joules > 0 {
                change = averageWatts / (earlier.joules / beforeSampled) - 1
            }
        }

        return AppUsageReport(
            app: known.identity, granularity: granularity, joules: total, batteryTime: entry?.batteryTime, share: entry?.share ?? 0,
            rank: report.rank(of: key), appCount: report.apps.count, activeDays: entry?.activeDays ?? 0,
            dayCount: Self.dayCount(from: report.start, to: report.end, calendar: calendar), averageWatts: averageWatts,
            periods: report.periods.indices.map { index in
                let period = report.periods[index]
                return .init(
                    start: period.start, end: period.end, joules: joules[index], batteryTime: report.averageWatts.map { joules[index] / $0 })
            },
            hoursOfDay: hoursOfDay, busiestHour: Self.busiestHour(hoursOfDay), firstSeen: known.firstSeen, lastSeen: known.lastSeen,
            change: change)
    }

    /// The hour that stands out: measured for at least half an hour over the days, and using at least a third more
    /// than the average of the others. Otherwise there isn't one worth naming.
    static func busiestHour(_ hours: [AppUsageReport.HourOfDay]) -> Int? {
        let known = hours.filter { $0.sampledSeconds >= 30 * 60 }.compactMap { hour in hour.watts.map { (hour.hour, $0) } }
        guard known.count >= 3, let top = known.max(by: { $0.1 < $1.1 }), top.1 > 0 else { return nil }
        let others = known.filter { $0.0 != top.0 }.map(\.1)
        let usual = others.reduce(0, +) / Double(others.count)
        return top.1 >= usual * 4 / 3 ? top.0 : nil
    }

    /// The periods from the one `start` is in, through the one `end` is in (the last ends at `end`).
    static func periods(
        from start: Date, to end: Date, granularity: UsageReport.Granularity, calendar: Calendar
    ) -> [UsageReport.Period] {
        guard end > start else { return [] }
        let first: Date
        switch granularity {
        case .hour: first = hourStart(of: start)
        case .day: first = calendar.startOfDay(for: start)
        case .week: first = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? calendar.startOfDay(for: start)
        }
        var periods: [UsageReport.Period] = []
        var cursor = first
        // A year by the hour is the most anyone asks for; the cap keeps a wrong clock from asking for more.
        while cursor < end, periods.count < 24 * 400 {
            let next: Date
            switch granularity {
            case .hour: next = cursor.addingTimeInterval(3600)
            case .day: next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(24 * 3600)
            case .week: next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? cursor.addingTimeInterval(7 * 24 * 3600)
            }
            periods.append(UsageReport.Period(start: cursor, end: min(next, end)))
            cursor = next
        }
        return periods
    }

    /// Calendar days touched by `start..<end`.
    static func dayCount(from start: Date, to end: Date, calendar: Calendar) -> Int {
        guard end > start else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: end).day ?? 0
        return max(days + (calendar.startOfDay(for: end) == end ? 0 : 1), 1)
    }
}
