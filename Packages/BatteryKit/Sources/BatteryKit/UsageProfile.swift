import Foundation

/// Two weeks of the battery in summary: for every hour, how long the Mac ran on battery, how much of it was used,
/// how much power the Mac drew, and which apps used it.
///
/// It's what "more than usual" and "a new app" compare against, and what the panel's ten-day chart draws. Built from
/// the same readings ``BatteryHistory`` gets (level changes, and samples every few minutes on battery), so it costs
/// no extra sampling, and it stays small: at most ``retention`` / 1 hour entries, each with the apps that used energy
/// in it.
public struct UsageProfile: Sendable, Equatable {
    /// One clock hour.
    public struct Hour: Sendable, Equatable, Identifiable {
        /// The start of the hour.
        public var start: Date
        /// Time on battery in this hour, from the level readings. Includes time asleep.
        public var batterySeconds: Double = 0
        /// Percentage points used on battery in this hour.
        public var drained: Int = 0
        /// How much of the hour the energy samples cover.
        public var sampledSeconds: Double = 0
        /// The Mac's own energy over the part of the samples with a power reading, and how long that part is.
        public var systemJoules: Double = 0
        public var measuredSeconds: Double = 0
        /// Joules used by each app, keyed by ``BatteryHistory/AppIdentity/key``.
        public var appJoules: [String: Double] = [:]

        public init(start: Date) {
            self.start = start
        }

        public init(
            start: Date, batterySeconds: Double, drained: Int, sampledSeconds: Double, systemJoules: Double, measuredSeconds: Double,
            appJoules: [String: Double]
        ) {
            self.start = start
            self.batterySeconds = batterySeconds
            self.drained = drained
            self.sampledSeconds = sampledSeconds
            self.systemJoules = systemJoules
            self.measuredSeconds = measuredSeconds
            self.appJoules = appJoules
        }

        public var id: Date { start }

        /// The Mac's average power draw while measured; `nil` without power readings.
        public var averageWatts: Double? { measuredSeconds > 0 ? systemJoules / measuredSeconds : nil }
    }

    /// An app the profile has seen, with when it first and last showed up among the hungriest.
    public struct App: Sendable, Equatable {
        public var identity: BatteryHistory.AppIdentity
        public var firstSeen: Date
        public var lastSeen: Date
        /// When the "new app" notification went out for it; it's only sent once.
        public var notifiedAsNew: Date?
        /// When its "new app" line in the panel was dismissed.
        public var dismissedAsNew: Date?

        public init(
            identity: BatteryHistory.AppIdentity, firstSeen: Date, lastSeen: Date, notifiedAsNew: Date? = nil, dismissedAsNew: Date? = nil
        ) {
            self.identity = identity
            self.firstSeen = firstSeen
            self.lastSeen = lastSeen
            self.notifiedAsNew = notifiedAsNew
            self.dismissedAsNew = dismissedAsNew
        }
    }

    /// One day, for the ten-day chart.
    public struct Day: Sendable, Equatable, Identifiable {
        public let start: Date
        public let batterySeconds: Double
        /// Percentage points used on battery.
        public let drained: Int

        public var id: Date { start }
    }

    public static let retention: TimeInterval = 14 * 24 * 3600
    /// How long hours are kept for, from two weeks (the default) to a year, as chosen in Settings. Insights still
    /// only look at the last two weeks; the rest is there to look back on and export.
    public var retention: TimeInterval = UsageProfile.retention {
        didSet { if retention < oldValue { trim() } }
    }
    /// A gap between two level readings longer than this isn't counted at all: the app wasn't running, so what the
    /// battery did in between is unknown. Shorter ones are usually the Mac asleep on battery, which does count.
    static let longestGap: TimeInterval = 24 * 3600
    /// A sample longer than this spans sleep: the power reading taken at its end says nothing about the rest of it.
    public static let longestMeasuredSample: TimeInterval = 15 * 60

    /// In date order, one per clock hour that saw any use.
    public private(set) var hours: [Hour] = []
    public private(set) var apps: [String: App] = [:]
    /// The last level reading, to know what the time since it was spent on.
    public private(set) var lastLevel: BatteryHistory.LevelPoint?

    public init() {}

    /// A profile put back together from what was saved.
    public init(
        hours: [Hour], apps: [String: App], lastLevel: BatteryHistory.LevelPoint?, now: Date = Date(),
        retention: TimeInterval = UsageProfile.retention
    ) {
        self.retention = retention
        self.hours = hours.sorted { $0.start < $1.start }
        self.apps = apps
        self.lastLevel = lastLevel
        trim(now: now)
    }

    public var isEmpty: Bool { hours.isEmpty }

    /// The start of the clock hour `date` falls in. Hours are counted from a fixed point rather than the calendar, so
    /// they stay put when the time zone changes.
    public static func hourStart(of date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600)
    }

    // MARK: - Recording

    /// Records a level reading: the time since the one before was spent on battery or not, and a lower level on
    /// battery is battery used. Returns the hours that changed.
    @discardableResult
    public mutating func record(level point: BatteryHistory.LevelPoint) -> Set<Date> {
        defer { lastLevel = point }
        guard let last = lastLevel, point.date > last.date, !last.isPluggedIn else { return [] }
        let gap = point.date.timeIntervalSince(last.date)
        guard gap <= Self.longestGap else { return [] }
        var changed = spread(from: last.date, to: point.date) { $0.batterySeconds += $1 }
        if !point.isPluggedIn, point.percentage < last.percentage {
            let drop = last.percentage - point.percentage
            if gap <= 3600 {
                // macOS reports each percent as it goes, so a drop in a short gap happened just before the reading.
                let start = Self.hourStart(of: point.date)
                update(start) { $0.drained += drop }
                changed.insert(start)
            } else {
                // Asleep, most likely: it went down steadily over the whole gap, so each hour gets its share.
                var elapsed = 0.0
                var given = 0
                changed.formUnion(
                    spread(from: last.date, to: point.date) { hour, seconds in
                        elapsed += seconds
                        let due = Int((Double(drop) * elapsed / gap).rounded())
                        hour.drained += due - given
                        given = due
                    })
            }
        }
        trim(now: point.date)
        return changed
    }

    /// Records an energy sample, split across the hours it covers. Returns the hours that changed.
    @discardableResult
    public mutating func record(_ sample: BatteryHistory.EnergySample, apps identities: [String: BatteryHistory.AppIdentity]) -> Set<Date> {
        guard sample.seconds > 0 else { return [] }
        let changed = spread(from: sample.start, to: sample.date) { hour, seconds in
            let fraction = seconds / sample.seconds
            hour.sampledSeconds += seconds
            if let watts = sample.systemWatts, watts > 0, sample.seconds <= Self.longestMeasuredSample {
                hour.systemJoules += watts * seconds
                hour.measuredSeconds += seconds
            }
            for (key, joules) in sample.joules { hour.appJoules[key, default: 0] += joules * fraction }
        }
        for key in sample.joules.keys {
            guard let identity = identities[key] else { continue }
            if var app = apps[key] {
                app.identity = identity
                app.lastSeen = max(app.lastSeen, sample.date)
                apps[key] = app
            } else {
                apps[key] = App(identity: identity, firstSeen: sample.date, lastSeen: sample.date)
            }
        }
        trim(now: sample.date)
        return changed
    }

    /// The "new app" notification went out for an app.
    public mutating func markNotifiedAsNew(_ key: String, at date: Date = Date()) {
        apps[key]?.notifiedAsNew = date
    }

    /// Its line in the panel was dismissed.
    public mutating func markDismissedAsNew(_ key: String, at date: Date = Date()) {
        apps[key]?.dismissedAsNew = date
    }

    public mutating func removeAll() {
        let retention = retention
        self = UsageProfile()
        self.retention = retention
    }

    /// Drops hours older than ``retention``, and apps not seen since.
    public mutating func trim(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retention)
        if let oldest = hours.first, oldest.start < cutoff {
            hours.removeFirst(BatteryHistory.partitionIndex(in: hours) { $0.start < cutoff })
        }
        if apps.values.contains(where: { $0.lastSeen < cutoff }) {
            apps = apps.filter { $0.value.lastSeen >= cutoff }
        }
    }

    /// Calls `body` for each hour between `start` and `end` with the seconds of it inside, creating hours as needed.
    private mutating func spread(from start: Date, to end: Date, _ body: (inout Hour, Double) -> Void) -> Set<Date> {
        var changed = Set<Date>()
        var cursor = start
        while cursor < end {
            let hour = Self.hourStart(of: cursor)
            let next = min(hour.addingTimeInterval(3600), end)
            let seconds = next.timeIntervalSince(cursor)
            update(hour) { body(&$0, seconds) }
            changed.insert(hour)
            cursor = next
        }
        return changed
    }

    private mutating func update(_ start: Date, _ body: (inout Hour) -> Void) {
        // Nearly always the last hour, or a new one after it.
        if let last = hours.indices.last, hours[last].start == start {
            body(&hours[last])
            return
        }
        let index = BatteryHistory.partitionIndex(in: hours) { $0.start < start }
        if index < hours.endIndex, hours[index].start == start {
            body(&hours[index])
        } else {
            var hour = Hour(start: start)
            body(&hour)
            hours.insert(hour, at: index)
        }
    }

    /// The hour that starts at `start`, if it saw any use.
    public func hour(at start: Date) -> Hour? {
        let index = BatteryHistory.partitionIndex(in: hours) { $0.start < start }
        return index < hours.endIndex && hours[index].start == start ? hours[index] : nil
    }

    // MARK: - Reading

    /// The hours from `start` on.
    public func hours(since start: Date) -> ArraySlice<Hour> {
        hours[BatteryHistory.partitionIndex(in: hours) { $0.start.addingTimeInterval(3600) <= start }...]
    }

    /// The last `count` days, oldest first, ending with today, by `calendar`'s days.
    public func days(_ count: Int, endingAt now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        guard let first = starts.first else { return [] }
        var seconds = [Double](repeating: 0, count: starts.count)
        var drained = [Int](repeating: 0, count: starts.count)
        var index = 0
        for hour in hours(since: first) {
            while index + 1 < starts.count, hour.start >= starts[index + 1] { index += 1 }
            guard hour.start >= starts[index] else { continue }
            seconds[index] += hour.batterySeconds
            drained[index] += hour.drained
        }
        return starts.indices.map { Day(start: starts[$0], batterySeconds: seconds[$0], drained: drained[$0]) }
    }

    /// The apps that used the most energy from `start` on, most first, the way ``BatteryHistory/appEnergy(since:)``
    /// counts them.
    public func appEnergy(since start: Date) -> [BatteryHistory.AppEnergy] {
        var totals: [String: Double] = [:]
        var systemJoules = 0.0
        var measured = 0.0
        for hour in hours(since: start) {
            for (key, joules) in hour.appJoules { totals[key, default: 0] += joules }
            systemJoules += hour.systemJoules
            measured += hour.measuredSeconds
        }
        let averageWatts = measured > 0 ? systemJoules / measured : nil
        return
            totals
            .compactMap { key, joules in
                apps[key].map { BatteryHistory.AppEnergy(app: $0.identity, joules: joules, batteryTime: averageWatts.map { joules / $0 }) }
            }
            .sorted { $0.joules != $1.joules ? $0.joules > $1.joules : $0.id < $1.id }
    }

    /// How much time on battery the samples from `start` on cover.
    public func sampledTime(since start: Date) -> TimeInterval {
        hours(since: start).reduce(0) { $0 + $1.sampledSeconds }
    }

    /// The days, by `calendar`, that have at least `minimum` of measured time on battery.
    public func measuredDays(minimum: TimeInterval = 30 * 60, calendar: Calendar = .current) -> Set<Date> {
        var perDay: [Date: Double] = [:]
        for hour in hours { perDay[calendar.startOfDay(for: hour.start), default: 0] += hour.measuredSeconds }
        return Set(perDay.filter { $0.value >= minimum }.keys)
    }
}
