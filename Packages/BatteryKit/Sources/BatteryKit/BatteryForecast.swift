import Foundation

/// Where the battery level is headed from now, on battery: a line to draw past "now" in the panel's chart, and when
/// it should reach a low level and run out.
///
/// It starts at the pace the Mac is going now (macOS's own time left, which follows the current draw) and, over the
/// next hour or two, leans towards how fast the battery usually goes at each hour of the day, from the hourly history.
/// So a forecast at 9:00 knows the afternoon is usually busier. Without history, it's the current pace, straight on.
public struct BatteryForecast: Sendable, Equatable {
    /// What the forecast stands on.
    public enum Basis: Sendable, Equatable {
        /// The current pace only: there isn't enough history for this time of day yet.
        case currentPace
        /// The current pace, then how the battery usually goes at these hours.
        case usualDay
    }

    /// One step of the line, every ``step``.
    public struct Point: Sendable, Equatable, Identifiable {
        public let date: Date
        /// 0–100, not rounded: it's a line, not a reading.
        public let percentage: Double
        public var id: Date { date }

        public init(date: Date, percentage: Double) {
            self.date = date
            self.percentage = percentage
        }
    }

    /// From now (the current level) to empty or the end of ``horizon``, whichever comes first.
    public let points: [Point]
    /// When it should reach ``lowLevel``, rounded down to five minutes; `nil` if it's already there, or not within the horizon.
    public let reachesLow: Date?
    /// When it should run out, rounded down to five minutes; `nil` if not within the horizon.
    public let runsOut: Date?
    /// The level ``reachesLow`` is for.
    public let lowLevel: Int
    public let basis: Basis

    /// The line's resolution.
    public static let step: TimeInterval = 15 * 60
    /// How far ahead it looks. Further than this, what you'll do with the Mac is anyone's guess.
    public static let horizon: TimeInterval = 12 * 3600
    /// How quickly the current pace gives way to the usual one: after this long, they count about the same.
    public static let paceHalfLife: TimeInterval = 50 * 60
    /// An hour of the day needs this many earlier days with time on battery in it to say what's usual then.
    public static let daysNeeded = 3
    /// A day counts towards an hour once it had this much battery time in it.
    public static let minimumHourSeconds: TimeInterval = 15 * 60
    /// Slower than this (percentage points an hour) isn't going anywhere to forecast: a Mac idling at the login window, say.
    public static let slowestRate = 0.5
    /// Faster than this is a reading gone wrong, not a pace.
    public static let fastestRate = 60.0
}

public enum ForecastModel {
    /// The forecast from `snapshot` at `now`; `nil` unless the Mac is on battery and there's a pace to go on.
    ///
    /// - Parameters:
    ///   - profile: the hourly history, for how the battery usually goes at each hour of the day.
    ///   - history: the last day, for the current pace while macOS is still working out the time left.
    ///   - lowLevel: the level ``BatteryForecast/reachesLow`` is for.
    public static func forecast(
        snapshot: BatterySnapshot, profile: UsageProfile, history: BatteryHistory, now: Date = Date(), lowLevel: Int = 20,
        calendar: Calendar = .current
    ) -> BatteryForecast? {
        guard snapshot.hasBattery, snapshot.chargeState == .discharging, snapshot.percentage > 0 else { return nil }
        let usual = usualRates(profile: profile, now: now, calendar: calendar)
        let current = currentRate(snapshot: snapshot, history: history, now: now) ?? usual.overall
        guard let current else { return nil }
        let basis: BatteryForecast.Basis = usual.byHour.isEmpty ? .currentPace : .usualDay

        let step = BatteryForecast.step
        let fine: TimeInterval = 5 * 60
        var level = Double(snapshot.percentage)
        var date = now
        var points = [BatteryForecast.Point(date: now, percentage: level)]
        var reachesLow: Date?
        var runsOut: Date?
        let end = now.addingTimeInterval(BatteryForecast.horizon)
        var nextPoint = now.addingTimeInterval(step)
        while date < end, level > 0 {
            let elapsed = date.timeIntervalSince(now)
            let hour = calendar.component(.hour, from: date)
            let usualRate = usual.byHour[hour] ?? usual.overall ?? current
            // The current pace counts fully now and fades: half as much after a half-life, and so on.
            let weight = pow(0.5, elapsed / BatteryForecast.paceHalfLife)
            let rate = clamp(weight * current + (1 - weight) * usualRate)
            let before = level
            level -= rate * fine / 3600
            date = date.addingTimeInterval(fine)
            if reachesLow == nil, before > Double(lowLevel), level <= Double(lowLevel) {
                reachesLow = crossing(at: Double(lowLevel), from: before, to: level, ending: date, over: fine)
            }
            if level <= 0 {
                runsOut = crossing(at: 0, from: before, to: level, ending: date, over: fine)
                points.append(BatteryForecast.Point(date: runsOut ?? date, percentage: 0))
                break
            }
            if date >= nextPoint {
                points.append(BatteryForecast.Point(date: date, percentage: level))
                nextPoint = nextPoint.addingTimeInterval(step)
            }
        }
        return BatteryForecast(
            points: points, reachesLow: reachesLow.map { MeetingCheck.roundedDown($0) }, runsOut: runsOut.map { MeetingCheck.roundedDown($0) },
            lowLevel: lowLevel, basis: basis)
    }

    /// When, within the last step, the level passed `target`.
    private static func crossing(at target: Double, from before: Double, to after: Double, ending: Date, over duration: TimeInterval) -> Date {
        guard before > after else { return ending }
        let share = (before - target) / (before - after)
        return ending.addingTimeInterval(-duration * (1 - share))
    }

    private static func clamp(_ rate: Double) -> Double {
        min(max(rate, BatteryForecast.slowestRate), BatteryForecast.fastestRate)
    }

    /// Percentage points an hour at the pace the Mac is going now: from macOS's time left, or else from how the level
    /// fell over the last hour of the history. `nil` when neither says.
    static func currentRate(snapshot: BatterySnapshot, history: BatteryHistory, now: Date) -> Double? {
        if let remaining = snapshot.timeRemaining, remaining >= 60 {
            let rate = Double(snapshot.percentage) / (remaining / 3600)
            if rate.isFinite, rate > 0 { return clamp(rate) }
        }
        // macOS is still working it out (just unplugged, or just woken): the level's own fall over the last hour,
        // since the last time it was plugged in.
        let since = now.addingTimeInterval(-3600)
        let levels = history.levels(since: since)
        guard let lastPlugged = levels.lastIndex(where: \.isPluggedIn) ?? (levels.isEmpty ? nil : -1) else { return nil }
        let onBattery = levels[(lastPlugged + 1)...].filter { !$0.isPluggedIn }
        guard let first = onBattery.first else { return nil }
        let hours = now.timeIntervalSince(first.date) / 3600
        let fallen = first.percentage - snapshot.percentage
        guard hours >= 0.33, fallen >= 2 else { return nil }
        return clamp(Double(fallen) / hours)
    }

    /// How fast the battery usually goes at each hour of the day (percentage points an hour of battery time), over the
    /// last two weeks before today, and over all of them together. Hours without enough days of history are left out.
    static func usualRates(profile: UsageProfile, now: Date, calendar: Calendar) -> (byHour: [Int: Double], overall: Double?) {
        let today = calendar.startOfDay(for: now)
        let since = today.addingTimeInterval(-UsageProfile.retention)
        var drained: [Int: Int] = [:]
        var seconds: [Int: Double] = [:]
        var days: [Int: Int] = [:]
        var totalDrained = 0
        var totalSeconds = 0.0
        for hour in profile.hours(since: since) where hour.start < today && hour.batterySeconds > 0 {
            let hourOfDay = calendar.component(.hour, from: hour.start)
            drained[hourOfDay, default: 0] += hour.drained
            seconds[hourOfDay, default: 0] += hour.batterySeconds
            totalDrained += hour.drained
            totalSeconds += hour.batterySeconds
            // Hours are one a day for each hour of the day, so each one with enough in it is one more day.
            if hour.batterySeconds >= BatteryForecast.minimumHourSeconds { days[hourOfDay, default: 0] += 1 }
        }
        var byHour: [Int: Double] = [:]
        for (hourOfDay, count) in days where count >= BatteryForecast.daysNeeded {
            guard let time = seconds[hourOfDay], time > 0 else { continue }
            byHour[hourOfDay] = clamp(Double(drained[hourOfDay] ?? 0) / (time / 3600))
        }
        // Overall needs a few hours' worth, or it's one afternoon speaking for every day.
        let overall = totalSeconds >= 4 * 3600 ? clamp(Double(totalDrained) / (totalSeconds / 3600)) : nil
        return (byHour, overall)
    }
}
