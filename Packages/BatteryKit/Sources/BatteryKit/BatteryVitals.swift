import Foundation

/// A run of readings in brief: how many, their total, the lowest and the highest. Enough for an average and a range,
/// and two of them merge into one, so hours add up to days and days to weeks.
public struct ReadingStats: Codable, Sendable, Equatable {
    public private(set) var count = 0
    public private(set) var sum = 0.0
    public private(set) var low: Double?
    public private(set) var high: Double?

    public init() {}

    public init(_ values: [Double]) {
        for value in values { add(value) }
    }

    public var isEmpty: Bool { count == 0 }
    public var mean: Double? { count > 0 ? sum / Double(count) : nil }

    public mutating func add(_ value: Double?) {
        guard let value, value.isFinite else { return }
        count += 1
        sum += value
        low = min(low ?? value, value)
        high = max(high ?? value, value)
    }

    public mutating func merge(_ other: ReadingStats) {
        guard other.count > 0, let otherLow = other.low, let otherHigh = other.high else { return }
        count += other.count
        sum += other.sum
        low = min(low ?? otherLow, otherLow)
        high = max(high ?? otherHigh, otherHigh)
    }
}

/// What the battery and the Mac were doing at one moment: one reading for ``BatteryVitals``.
public struct VitalsReading: Sendable, Equatable {
    /// °C.
    public var temperature: Double?
    /// Volts.
    public var voltage: Double?
    /// Watts into the battery (positive, charging) or out of it (negative).
    public var batteryWatts: Double?
    /// What the whole Mac draws.
    public var systemWatts: Double?
    /// What comes in from the charger; `nil` on battery.
    public var chargerWatts: Double?
    /// The charge level, 0–100.
    public var percentage: Int?
    public var isPluggedIn: Bool
    /// Plugged in but not charging: held at a charge limit, by Optimized Battery Charging, or full.
    public var isHolding: Bool
    /// It started holding since the reading before: it just reached its limit (or full).
    public var reachedLimit: Bool

    public init(
        temperature: Double? = nil, voltage: Double? = nil, batteryWatts: Double? = nil, systemWatts: Double? = nil, chargerWatts: Double? = nil,
        percentage: Int? = nil, isPluggedIn: Bool = false, isHolding: Bool = false, reachedLimit: Bool = false
    ) {
        self.temperature = temperature
        self.voltage = voltage
        self.batteryWatts = batteryWatts
        self.systemWatts = systemWatts
        self.chargerWatts = chargerWatts
        self.percentage = percentage
        self.isPluggedIn = isPluggedIn
        self.isHolding = isPluggedIn && isHolding
        self.reachedLimit = isPluggedIn && isHolding && reachedLimit
    }

    /// From what the battery controller reads.
    public init(
        readings: BatteryReadings, flow: PowerFlow?, percentage: Int?, isPluggedIn: Bool, isHolding: Bool = false, reachedLimit: Bool = false
    ) {
        self.init(
            temperature: readings.temperature, voltage: readings.voltage, batteryWatts: readings.batteryWatts, systemWatts: flow?.systemWatts,
            chargerWatts: isPluggedIn ? flow?.chargerWatts : nil, percentage: percentage, isPluggedIn: isPluggedIn, isHolding: isHolding,
            reachedLimit: reachedLimit)
    }
}

/// Which readings to look at.
public enum VitalsFilter: String, Sendable, CaseIterable, Identifiable {
    case all
    case onBattery
    case pluggedIn

    public var id: Self { self }
}

/// A set of readings in brief: the range and average of each vital sign.
public struct VitalsStats: Codable, Sendable, Equatable {
    public private(set) var readings = 0
    public private(set) var temperature = ReadingStats()
    public private(set) var voltage = ReadingStats()
    /// Watts into the battery, while it charged.
    public private(set) var charging = ReadingStats()
    /// Watts out of it, as positive numbers, while it ran the Mac.
    public private(set) var discharging = ReadingStats()
    /// The whole Mac's draw.
    public private(set) var system = ReadingStats()
    /// What came from the charger, while plugged in.
    public private(set) var charger = ReadingStats()
    public private(set) var level = ReadingStats()
    /// Readings with the battery at ``BatteryReadings/Warmth/warmFrom`` or above.
    public private(set) var warm = 0
    /// Readings plugged in but not charging: held at a limit, or full.
    public private(set) var holding = 0
    /// Of those, the ones held at full (``fullFrom`` or more), where a battery wears fastest.
    public private(set) var holdingFull = 0
    /// How many times it reached its limit (or full) and started holding.
    public private(set) var limitReached = 0

    /// Holding at this level or above counts as sitting full.
    public static let fullFrom = 99

    /// Whether ``holding`` and ``limitReached`` were counted: hours from before 0.5.1 didn't, so their zeros say
    /// nothing.
    public private(set) var tracksHolding = false

    public init() {}

    public var isEmpty: Bool { readings == 0 }

    public mutating func add(_ reading: VitalsReading) {
        readings += 1
        temperature.add(reading.temperature)
        voltage.add(reading.voltage)
        if let watts = reading.batteryWatts {
            if watts > Self.idleWatts { charging.add(watts) } else if watts < -Self.idleWatts { discharging.add(-watts) }
        }
        system.add(reading.systemWatts)
        charger.add(reading.chargerWatts)
        level.add(reading.percentage.map(Double.init))
        if let celsius = reading.temperature, celsius >= BatteryReadings.Warmth.warmFrom { warm += 1 }
        tracksHolding = true
        if reading.isHolding {
            holding += 1
            if (reading.percentage ?? 0) >= Self.fullFrom { holdingFull += 1 }
        }
        if reading.reachedLimit { limitReached += 1 }
    }

    public mutating func merge(_ other: VitalsStats) {
        readings += other.readings
        temperature.merge(other.temperature)
        voltage.merge(other.voltage)
        charging.merge(other.charging)
        discharging.merge(other.discharging)
        system.merge(other.system)
        charger.merge(other.charger)
        level.merge(other.level)
        warm += other.warm
        if other.tracksHolding { tracksHolding = true }
        holding += other.holding
        holdingFull += other.holdingFull
        limitReached += other.limitReached
    }

    private enum CodingKeys: String, CodingKey {
        case readings, temperature, voltage, charging, discharging, system, charger, level, warm
        case holding, holdingFull, limitReached, tracksHolding
    }

    /// Hours saved before 0.5.1 have no holding counts, and say so with ``tracksHolding``.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readings = try container.decode(Int.self, forKey: .readings)
        temperature = try container.decode(ReadingStats.self, forKey: .temperature)
        voltage = try container.decode(ReadingStats.self, forKey: .voltage)
        charging = try container.decode(ReadingStats.self, forKey: .charging)
        discharging = try container.decode(ReadingStats.self, forKey: .discharging)
        system = try container.decode(ReadingStats.self, forKey: .system)
        charger = try container.decode(ReadingStats.self, forKey: .charger)
        level = try container.decode(ReadingStats.self, forKey: .level)
        warm = try container.decode(Int.self, forKey: .warm)
        holding = try container.decodeIfPresent(Int.self, forKey: .holding) ?? 0
        holdingFull = try container.decodeIfPresent(Int.self, forKey: .holdingFull) ?? 0
        limitReached = try container.decodeIfPresent(Int.self, forKey: .limitReached) ?? 0
        tracksHolding = try container.decodeIfPresent(Bool.self, forKey: .tracksHolding) ?? false
    }

    /// A battery moving less than this is resting: neither charging nor running the Mac.
    static let idleWatts = 0.1
}

/// The battery's vital signs over time: its temperature, voltage, charging and discharging, what the Mac drew and the
/// charger gave, hour by hour, and its health (maximum capacity and charge cycles) day by day.
///
/// Readings come every few minutes, plugged in or not, and go into their hour's summary at once, so a year is 8,760
/// small rows whatever the reading rate. Hours are kept as long as the rest of the history; health days for good, as
/// the wear of a battery shows over years, and a year of them is a few kilobytes.
public struct BatteryVitals: Codable, Sendable, Equatable {
    /// One hour's readings, on battery and plugged in apart, so either can be looked at alone.
    public struct Hour: Codable, Sendable, Equatable, Identifiable {
        public let start: Date
        public var onBattery = VitalsStats()
        public var pluggedIn = VitalsStats()

        public init(start: Date) {
            self.start = start
        }

        public var id: Date { start }
        public var readings: Int { onBattery.readings + pluggedIn.readings }

        /// Every reading together.
        public var all: VitalsStats {
            var all = onBattery
            all.merge(pluggedIn)
            return all
        }

        public func stats(_ filter: VitalsFilter) -> VitalsStats {
            switch filter {
            case .all: all
            case .onBattery: onBattery
            case .pluggedIn: pluggedIn
            }
        }

        mutating func add(_ reading: VitalsReading) {
            if reading.isPluggedIn { pluggedIn.add(reading) } else { onBattery.add(reading) }
        }
    }

    /// The battery's health on one day.
    public struct HealthDay: Codable, Sendable, Equatable, Identifiable {
        public let day: Date
        /// 0–1, against when it was new.
        public var maximumCapacity: Double?
        public var cycleCount: Int?

        public init(day: Date, maximumCapacity: Double?, cycleCount: Int?) {
            self.day = day
            self.maximumCapacity = maximumCapacity
            self.cycleCount = cycleCount
        }

        public var id: Date { day }
    }

    public private(set) var hours: [Hour] = []
    public private(set) var health: [HealthDay] = []
    public var retention: TimeInterval

    public init(hours: [Hour] = [], health: [HealthDay] = [], retention: TimeInterval = UsageProfile.retention, now: Date = Date()) {
        self.hours = hours.sorted { $0.start < $1.start }
        self.health = health.sorted { $0.day < $1.day }
        self.retention = retention
        trim(now: now)
    }

    public var isEmpty: Bool { hours.isEmpty && health.isEmpty }

    // MARK: - Recording

    /// Adds a reading to its hour. Returns the hour's start, for the store to write that row.
    @discardableResult
    public mutating func record(_ reading: VitalsReading, at date: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        if let last = hours.indices.last, hours[last].start == start {
            hours[last].add(reading)
        } else if let index = hours.firstIndex(where: { $0.start == start }) {
            hours[index].add(reading)
        } else {
            var hour = Hour(start: start)
            hour.add(reading)
            let index = BatteryHistory.partitionIndex(in: hours) { $0.start < start }
            hours.insert(hour, at: index)
        }
        trim(now: date)
        return start
    }

    /// Notes the battery's health for the day. Returns the day when it changed something.
    @discardableResult
    public mutating func record(health reading: BatteryHealth, at date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard reading.maximumCapacity != nil || reading.cycleCount != nil else { return nil }
        let day = calendar.startOfDay(for: date)
        let entry = HealthDay(day: day, maximumCapacity: reading.maximumCapacity, cycleCount: reading.cycleCount)
        if let index = health.firstIndex(where: { $0.day == day }) {
            guard health[index] != entry else { return nil }
            health[index] = entry
        } else {
            health.insert(entry, at: BatteryHistory.partitionIndex(in: health) { $0.day < day })
        }
        return day
    }

    /// The hour's summary, if there's one.
    public func hour(at start: Date) -> Hour? {
        let index = BatteryHistory.partitionIndex(in: hours) { $0.start < start }
        return index < hours.endIndex && hours[index].start == start ? hours[index] : nil
    }

    public func healthDay(at day: Date) -> HealthDay? { health.first { $0.day == day } }

    /// Lets go of hours older than ``retention``. Health days stay.
    public mutating func trim(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retention)
        guard let first = hours.first, first.start < cutoff else { return }
        hours.removeFirst(BatteryHistory.partitionIndex(in: hours) { $0.start < cutoff })
    }

    public mutating func removeAll() {
        hours = []
        health = []
    }

    // MARK: - Reading

    /// The vitals from `start` to `end`, in hours, days or weeks, and by the hour of the day; only those on battery
    /// or plugged in, if `filter` says so.
    public func report(
        from start: Date, to end: Date, granularity: UsageReport.Granularity, filter: VitalsFilter = .all, calendar: Calendar = .current
    ) -> VitalsReport {
        let component: Calendar.Component =
            switch granularity {
            case .hour: .hour
            case .day: .day
            case .week: .weekOfYear
            }
        var periods: [VitalsReport.Period] = []
        var cursor = calendar.dateInterval(of: component, for: start)?.start ?? start
        while cursor < end {
            let next = calendar.date(byAdding: component, value: 1, to: cursor) ?? end
            periods.append(VitalsReport.Period(start: cursor, end: next))
            cursor = next
        }
        guard !periods.isEmpty else {
            return VitalsReport(granularity: granularity, filter: filter, periods: [], hoursOfDay: [], health: [], healthBefore: nil)
        }

        var whole = VitalsReport.Period(start: periods[0].start, end: end)
        var hoursOfDay = (0..<24).map { VitalsReport.HourOfDay(hour: $0) }
        var index = 0
        let first = BatteryHistory.partitionIndex(in: hours) { $0.start < periods[0].start }
        for hour in hours[first...] {
            guard hour.start < end else { break }
            while index < periods.count - 1, hour.start >= periods[index].end { index += 1 }
            periods[index].add(hour, filter: filter)
            whole.add(hour, filter: filter)
            hoursOfDay[calendar.component(.hour, from: hour.start) % 24].stats.merge(hour.stats(filter))
        }
        let rangeStart = calendar.startOfDay(for: periods[0].start)
        let inRange = health.filter { $0.day >= rangeStart && $0.day < end }
        let before = health.last { $0.day < rangeStart }
        var report = VitalsReport(
            granularity: granularity, filter: filter, periods: periods, hoursOfDay: hoursOfDay, health: inRange, healthBefore: before)
        report.whole = whole
        return report
    }
}

/// How long the Mac spent on battery and on the charger, and what the battery did there, over some hours.
public struct ChargeTime: Sendable, Equatable {
    public var onBattery = 0.0
    public var charging = 0.0
    /// Plugged in and held below full: at a charge limit, or by Optimized Battery Charging.
    public var holding = 0.0
    /// Plugged in and held full.
    public var full = 0.0
    /// Times it reached its limit (or full) and started holding.
    public var limitReached = 0

    public init() {}

    public var pluggedIn: Double { charging + holding + full }
    public var total: Double { onBattery + pluggedIn }
    public var isEmpty: Bool { total <= 0 }

    /// About how long it stays on the charger once it's reached its limit (or full); `nil` before it has.
    public var heldPerArrival: Double? { limitReached > 0 ? (holding + full) / Double(limitReached) : nil }

    /// The time one reading stands for.
    public static let readingInterval: TimeInterval = 5 * 60

    mutating func add(_ hour: BatteryVitals.Hour) {
        guard hour.readings > 0, hour.pluggedIn.tracksHolding || hour.pluggedIn.readings == 0, hour.onBattery.tracksHolding || hour.onBattery.readings == 0
        else { return }
        let each = min(Self.readingInterval, 3600 / Double(hour.readings))
        let plugged = hour.pluggedIn
        onBattery += each * Double(hour.onBattery.readings)
        full += each * Double(plugged.holdingFull)
        holding += each * Double(plugged.holding - plugged.holdingFull)
        charging += each * Double(max(plugged.readings - plugged.holding, 0))
        limitReached += plugged.limitReached
    }

    mutating func merge(_ other: ChargeTime) {
        onBattery += other.onBattery
        charging += other.charging
        holding += other.holding
        full += other.full
        limitReached += other.limitReached
    }
}

/// ``BatteryVitals`` over a stretch of time, for charts: each hour, day or week, and the whole.
public struct VitalsReport: Sendable, Equatable {
    public struct Period: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        /// The readings the filter lets through.
        public var stats = VitalsStats()
        /// Every reading, and those plugged in, whatever the filter: for the share of time on the charger.
        public var allReadings = 0
        public var pluggedInReadings = 0
        /// Roughly how long it was warm, and how long the filtered readings cover: each reading stands for its share
        /// of its hour.
        public var warmSeconds = 0.0
        public var coveredSeconds = 0.0
        /// Where the time went, whatever the filter, from the hours that counted it (from 0.5.1): about how long the
        /// Mac was awake on battery, charging, holding below full, and holding full. Each reading stands for the five
        /// minutes until the next, or its share of the hour when there were more.
        public var charge = ChargeTime()

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }

        public var id: Date { start }
        public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
        public var isEmpty: Bool { stats.isEmpty }

        mutating func add(_ hour: BatteryVitals.Hour, filter: VitalsFilter) {
            let shown = hour.stats(filter)
            stats.merge(shown)
            allReadings += hour.readings
            pluggedInReadings += hour.pluggedIn.readings
            charge.add(hour)
            guard hour.readings > 0 else { return }
            coveredSeconds += 3600 * Double(shown.readings) / Double(hour.readings)
            warmSeconds += 3600 * Double(shown.warm) / Double(hour.readings)
        }
    }

    /// One hour of the day (0–23) over the whole stretch: when in the day it runs warm, or draws the most.
    public struct HourOfDay: Sendable, Equatable, Identifiable {
        public let hour: Int
        public var stats = VitalsStats()

        public var id: Int { hour }
    }

    public let granularity: UsageReport.Granularity
    public let filter: VitalsFilter
    public let periods: [Period]
    public let hoursOfDay: [HourOfDay]
    /// Health days in the stretch, oldest first.
    public let health: [BatteryVitals.HealthDay]
    /// The last health reading from before it, to say how much changed.
    public let healthBefore: BatteryVitals.HealthDay?
    /// Everything in the stretch together.
    public internal(set) var whole: Period

    init(
        granularity: UsageReport.Granularity, filter: VitalsFilter, periods: [Period], hoursOfDay: [HourOfDay], health: [BatteryVitals.HealthDay],
        healthBefore: BatteryVitals.HealthDay?
    ) {
        self.granularity = granularity
        self.filter = filter
        self.periods = periods
        self.hoursOfDay = hoursOfDay
        self.health = health
        self.healthBefore = healthBefore
        whole = Period(start: periods.first?.start ?? .distantPast, end: periods.last?.end ?? .distantPast)
    }

    public var isEmpty: Bool { whole.isEmpty }

    /// The share of the time on the charger, 0–1, whatever the filter.
    public var pluggedInShare: Double? { whole.allReadings > 0 ? Double(whole.pluggedInReadings) / Double(whole.allReadings) : nil }

    /// The hour of the day the Mac draws the most on average, when one stands out: a fifth or more above the others.
    public var busiestHour: Int? {
        let means = hoursOfDay.compactMap { hour in hour.stats.system.mean.map { (hour.hour, $0) } }
        guard means.count >= 6, let top = means.max(by: { $0.1 < $1.1 }) else { return nil }
        let others = means.filter { $0.0 != top.0 }.map(\.1)
        let average = others.reduce(0, +) / Double(others.count)
        return average > 0 && top.1 >= average * 1.2 ? top.0 : nil
    }

    /// The hottest hour of the day on average, when one stands out: a degree or more above the day's average.
    public var warmestHour: Int? {
        let means = hoursOfDay.compactMap { hour in hour.stats.temperature.mean.map { (hour.hour, $0) } }
        guard means.count >= 6, let top = means.max(by: { $0.1 < $1.1 }) else { return nil }
        let average = means.map(\.1).reduce(0, +) / Double(means.count)
        return top.1 - average >= 1 ? top.0 : nil
    }

    /// How the maximum capacity moved over the stretch, in points of capacity (0–1): negative is wear.
    public var capacityChange: Double? {
        guard let (first, last) = ends(\.maximumCapacity) else { return nil }
        return last - first
    }

    /// Charge cycles added over the stretch.
    public var cyclesAdded: Int? {
        guard let (first, last) = ends(\.cycleCount) else { return nil }
        return max(last - first, 0)
    }

    /// The first and last readings of something, from the last day before the stretch (or its first) to its last:
    /// `nil` unless they're two different days, as one reading has nothing to compare with.
    private func ends<Value>(_ value: KeyPath<BatteryVitals.HealthDay, Value?>) -> (Value, Value)? {
        let days = ([healthBefore].compactMap { $0 } + health).filter { $0[keyPath: value] != nil }
        guard let first = days.first, let last = days.last, first.day != last.day,
            let from = first[keyPath: value], let to = last[keyPath: value]
        else { return nil }
        return (from, to)
    }
}
