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

    public init(
        temperature: Double? = nil, voltage: Double? = nil, batteryWatts: Double? = nil, systemWatts: Double? = nil, chargerWatts: Double? = nil,
        percentage: Int? = nil, isPluggedIn: Bool = false
    ) {
        self.temperature = temperature
        self.voltage = voltage
        self.batteryWatts = batteryWatts
        self.systemWatts = systemWatts
        self.chargerWatts = chargerWatts
        self.percentage = percentage
        self.isPluggedIn = isPluggedIn
    }

    /// From what the battery controller reads.
    public init(readings: BatteryReadings, flow: PowerFlow?, percentage: Int?, isPluggedIn: Bool) {
        self.init(
            temperature: readings.temperature, voltage: readings.voltage, batteryWatts: readings.batteryWatts, systemWatts: flow?.systemWatts,
            chargerWatts: isPluggedIn ? flow?.chargerWatts : nil, percentage: percentage, isPluggedIn: isPluggedIn)
    }
}

/// The battery's vital signs over time: its temperature, voltage, charging and discharging, what the Mac drew and the
/// charger gave, hour by hour, and its health (maximum capacity and charge cycles) day by day.
///
/// Readings come every few minutes, plugged in or not, and go into their hour's summary at once, so a year is 8,760
/// small rows whatever the reading rate. Hours are kept as long as the rest of the history; health days for good, as
/// the wear of a battery shows over years, and a year of them is a few kilobytes.
public struct BatteryVitals: Codable, Sendable, Equatable {
    /// One hour's readings.
    public struct Hour: Codable, Sendable, Equatable, Identifiable {
        public let start: Date
        public var readings = 0
        public var temperature = ReadingStats()
        public var voltage = ReadingStats()
        /// Watts into the battery, while it charged.
        public var charging = ReadingStats()
        /// Watts out of it, as positive numbers, while it ran the Mac.
        public var discharging = ReadingStats()
        /// The whole Mac's draw.
        public var system = ReadingStats()
        /// What came from the charger, while plugged in.
        public var charger = ReadingStats()
        public var level = ReadingStats()
        /// Readings plugged in.
        public var pluggedIn = 0
        /// Readings with the battery at ``BatteryReadings/Warmth/warmFrom`` or above.
        public var warm = 0

        public init(start: Date) {
            self.start = start
        }

        public var id: Date { start }

        mutating func add(_ reading: VitalsReading) {
            readings += 1
            temperature.add(reading.temperature)
            voltage.add(reading.voltage)
            if let watts = reading.batteryWatts {
                if watts > Self.idleWatts { charging.add(watts) } else if watts < -Self.idleWatts { discharging.add(-watts) }
            }
            system.add(reading.systemWatts)
            charger.add(reading.chargerWatts)
            level.add(reading.percentage.map(Double.init))
            if reading.isPluggedIn { pluggedIn += 1 }
            if let celsius = reading.temperature, celsius >= BatteryReadings.Warmth.warmFrom { warm += 1 }
        }

        /// A battery moving less than this is resting: neither charging nor running the Mac.
        static let idleWatts = 0.1
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

    /// The vitals from `start` to `end`, in hours, days or weeks.
    public func report(from start: Date, to end: Date, granularity: UsageReport.Granularity, calendar: Calendar = .current) -> VitalsReport {
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
        guard !periods.isEmpty else { return VitalsReport(granularity: granularity, periods: [], health: [], healthBefore: nil) }

        var whole = VitalsReport.Period(start: periods[0].start, end: end)
        var index = 0
        let first = BatteryHistory.partitionIndex(in: hours) { $0.start < periods[0].start }
        for hour in hours[first...] {
            guard hour.start < end else { break }
            while index < periods.count - 1, hour.start >= periods[index].end { index += 1 }
            periods[index].add(hour)
            whole.add(hour)
        }
        let rangeStart = periods[0].start
        let inRange = health.filter { $0.day >= calendar.startOfDay(for: rangeStart) && $0.day < end }
        let before = health.last { $0.day < calendar.startOfDay(for: rangeStart) }
        var report = VitalsReport(granularity: granularity, periods: periods, health: inRange, healthBefore: before)
        report.whole = whole
        return report
    }
}

/// ``BatteryVitals`` over a stretch of time, for charts: each hour, day or week, and the whole.
public struct VitalsReport: Sendable, Equatable {
    public struct Period: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        public var readings = 0
        public var temperature = ReadingStats()
        public var voltage = ReadingStats()
        public var charging = ReadingStats()
        public var discharging = ReadingStats()
        public var system = ReadingStats()
        public var charger = ReadingStats()
        public var level = ReadingStats()
        public var pluggedIn = 0
        public var warm = 0
        /// Hours with readings, for how long something lasted: each reading stands for its share of its hour.
        public var warmSeconds = 0.0
        public var coveredSeconds = 0.0

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }

        public var id: Date { start }
        public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
        public var isEmpty: Bool { readings == 0 }

        mutating func add(_ hour: BatteryVitals.Hour) {
            readings += hour.readings
            temperature.merge(hour.temperature)
            voltage.merge(hour.voltage)
            charging.merge(hour.charging)
            discharging.merge(hour.discharging)
            system.merge(hour.system)
            charger.merge(hour.charger)
            level.merge(hour.level)
            pluggedIn += hour.pluggedIn
            warm += hour.warm
            if hour.readings > 0 {
                coveredSeconds += 3600
                warmSeconds += 3600 * Double(hour.warm) / Double(hour.readings)
            }
        }
    }

    public let granularity: UsageReport.Granularity
    public let periods: [Period]
    /// Health days in the stretch, oldest first.
    public let health: [BatteryVitals.HealthDay]
    /// The last health reading from before it, to say how much changed.
    public let healthBefore: BatteryVitals.HealthDay?
    /// Everything in the stretch together.
    public internal(set) var whole: Period

    init(granularity: UsageReport.Granularity, periods: [Period], health: [BatteryVitals.HealthDay], healthBefore: BatteryVitals.HealthDay?) {
        self.granularity = granularity
        self.periods = periods
        self.health = health
        self.healthBefore = healthBefore
        whole = Period(start: periods.first?.start ?? .distantPast, end: periods.last?.end ?? .distantPast)
    }

    public var isEmpty: Bool { whole.readings == 0 }

    /// The share of the time on the charger, 0–1.
    public var pluggedInShare: Double? { whole.readings > 0 ? Double(whole.pluggedIn) / Double(whole.readings) : nil }

    /// How the maximum capacity moved over the stretch, in points of capacity (0–1): negative is wear.
    public var capacityChange: Double? {
        guard let last = health.last(where: { $0.maximumCapacity != nil })?.maximumCapacity,
            let first = (healthBefore?.maximumCapacity) ?? health.first(where: { $0.maximumCapacity != nil })?.maximumCapacity
        else { return nil }
        return last - first
    }

    /// Charge cycles added over the stretch.
    public var cyclesAdded: Int? {
        guard let last = health.last(where: { $0.cycleCount != nil })?.cycleCount,
            let first = healthBefore?.cycleCount ?? health.first(where: { $0.cycleCount != nil })?.cycleCount
        else { return nil }
        return max(last - first, 0)
    }
}
