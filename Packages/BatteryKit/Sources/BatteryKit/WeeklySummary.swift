import Foundation

/// A week of the battery at a glance, compared with the week before: time on battery, battery used, the apps that used
/// the most, the app whose use grew the most, and the busiest day. For the weekly notification and Settings › History.
///
/// Weeks follow the calendar (Monday to Sunday, or wherever the user's week starts). A week still under way is compared
/// with the same days of the week before, so Wednesday isn't held up against a whole week.
public struct WeeklySummary: Sendable, Equatable {
    /// What one side of the comparison adds up to.
    public struct Totals: Sendable, Equatable {
        /// Time on battery, including time asleep.
        public let batterySeconds: Double
        /// Percentage points used on battery; can pass 100 when the Mac was charged in between.
        public let drained: Int
        /// The Mac's average draw on battery while measured; `nil` without power readings.
        public let averageWatts: Double?

        public init(batterySeconds: Double, drained: Int, averageWatts: Double?) {
            self.batterySeconds = batterySeconds
            self.drained = drained
            self.averageWatts = averageWatts
        }

        /// Full charges' worth: 230 points is 2.3.
        public var charges: Double { Double(drained) / 100 }
        var isEmpty: Bool { batterySeconds < 60 && drained == 0 }
    }

    /// An app whose use grew a lot since the week before.
    public struct Rise: Sendable, Equatable {
        public let app: BatteryHistory.AppIdentity
        /// Joules this week and the week before.
        public let joules: Double
        public let previousJoules: Double
        /// How many times as much: 2.5 for two and a half times.
        public var ratio: Double { previousJoules > 0 ? joules / previousJoules : .infinity }
    }

    /// The week (or the part of it so far), from the start of its first day.
    public let interval: DateInterval
    /// The week isn't over yet.
    public let isUnderWay: Bool
    public let totals: Totals
    /// The same days of the week before; `nil` when the history doesn't reach back that far.
    public let previous: Totals?
    /// The apps that used the most, most first; at most ``topAppCount``.
    public let topApps: [UsageReport.App]
    /// The app whose use grew the most, when it grew by at least half and by a fair amount.
    public let biggestRise: Rise?
    /// The day that used the most battery, and how much.
    public let busiestDay: (start: Date, drained: Int)?

    public static let topAppCount = 3
    /// An app's rise is worth pointing out from this much energy this week (a watt for two hours)…
    public static let minimumRiseJoules = 7200.0
    /// …and this many times what it used the week before.
    public static let minimumRiseRatio = 1.5

    /// How much more (or less) time on battery than the week before, as a share: 0.2 for 20% more. `nil` without a week
    /// before to compare with, or when it had next to none.
    public var batteryTimeChange: Double? { change(totals.batterySeconds, previous?.batterySeconds, minimum: 3600) }

    /// How much more (or less) battery was used than the week before, as a share.
    public var drainedChange: Double? { change(Double(totals.drained), previous.map { Double($0.drained) }, minimum: 10) }

    /// How much more (or less) the Mac drew on average than the week before, as a share.
    public var averageWattsChange: Double? { change(totals.averageWatts, previous?.averageWatts, minimum: 0.5) }

    /// The ratio less one, only when both sides have enough in them to compare.
    private func change(_ now: Double?, _ before: Double?, minimum: Double) -> Double? {
        guard let now, let before, before >= minimum else { return nil }
        return now / before - 1
    }

    /// Nothing to say: no time on battery that week.
    public var isEmpty: Bool { totals.isEmpty }

    public static func == (lhs: WeeklySummary, rhs: WeeklySummary) -> Bool {
        lhs.interval == rhs.interval && lhs.isUnderWay == rhs.isUnderWay && lhs.totals == rhs.totals && lhs.previous == rhs.previous
            && lhs.topApps == rhs.topApps && lhs.biggestRise == rhs.biggestRise && lhs.busiestDay?.start == rhs.busiestDay?.start
            && lhs.busiestDay?.drained == rhs.busiestDay?.drained
    }
}

extension UsageProfile {
    /// The week `date` falls in, up to `now` if it's still under way, compared with the same stretch a week earlier.
    public func weeklySummary(forWeekContaining date: Date, now: Date = Date(), calendar: Calendar = .current) -> WeeklySummary? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date), week.start <= now else { return nil }
        let isUnderWay = week.end > now
        let end = isUnderWay ? now : week.end
        let report = report(from: week.start, to: end, granularity: .day, calendar: calendar)

        // The same days a week earlier: the whole week before, unless this one's still going.
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start) ?? week.start.addingTimeInterval(-7 * 24 * 3600)
        let previousEnd = calendar.date(byAdding: .weekOfYear, value: -1, to: end) ?? end.addingTimeInterval(-7 * 24 * 3600)
        let reachesBack = hours.first.map { $0.start <= previousStart.addingTimeInterval(24 * 3600) } ?? false
        let previousReport = reachesBack ? self.report(from: previousStart, to: previousEnd, granularity: .day, calendar: calendar) : nil

        let totals = WeeklySummary.Totals(batterySeconds: report.batterySeconds, drained: report.drained, averageWatts: report.averageWatts)
        let previous = previousReport.map {
            WeeklySummary.Totals(batterySeconds: $0.batterySeconds, drained: $0.drained, averageWatts: $0.averageWatts)
        }

        var rise: WeeklySummary.Rise?
        if let previousReport {
            let before = Dictionary(previousReport.apps.map { ($0.id, $0.joules) }, uniquingKeysWith: +)
            for app in report.apps where app.joules >= WeeklySummary.minimumRiseJoules {
                let previousJoules = before[app.id] ?? 0
                // New this week counts as a rise too, but only once there was a week before to be new in.
                guard previousJoules == 0 || app.joules / previousJoules >= WeeklySummary.minimumRiseRatio else { continue }
                let extra = app.joules - previousJoules
                if let best = rise, best.joules - best.previousJoules >= extra { continue }
                rise = WeeklySummary.Rise(app: app.app, joules: app.joules, previousJoules: previousJoules)
            }
        }

        let busiest = report.periods.filter { $0.drained > 0 }.max { $0.drained != $1.drained ? $0.drained < $1.drained : $0.start > $1.start }
        return WeeklySummary(
            interval: DateInterval(start: week.start, end: end), isUnderWay: isUnderWay, totals: totals, previous: previous,
            topApps: Array(report.apps.prefix(WeeklySummary.topAppCount)), biggestRise: rise,
            busiestDay: busiest.map { ($0.start, $0.drained) })
    }

    /// The last week that's over, as of `now`.
    public func lastWeekSummary(now: Date = Date(), calendar: Calendar = .current) -> WeeklySummary? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        return weeklySummary(forWeekContaining: thisWeek.start.addingTimeInterval(-3600), now: now, calendar: calendar)
    }
}
