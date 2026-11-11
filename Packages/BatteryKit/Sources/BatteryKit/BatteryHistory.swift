import Foundation

/// The last day of the battery: its level over time, and which apps used
/// its energy while the Mac ran on battery.
///
/// Levels are recorded whenever macOS reports a change, which costs nothing.
/// App energy comes from samples taken every few minutes, only on battery
/// (see ``EnergySample``). Everything older than ``retention`` is dropped,
/// except the moment the Mac was last unplugged, which "since last charged"
/// needs however long ago it was.
public struct BatteryHistory: Codable, Sendable, Equatable {
    /// The battery level at one moment.
    public struct LevelPoint: Codable, Sendable, Equatable {
        public var date: Date
        /// 0–100.
        public var percentage: Int
        public var isPluggedIn: Bool

        public init(date: Date, percentage: Int, isPluggedIn: Bool) {
            self.date = date
            self.percentage = percentage
            self.isPluggedIn = isPluggedIn
        }
    }

    /// The energy each app used over a stretch of time on battery.
    public struct EnergySample: Codable, Sendable, Equatable {
        /// When the stretch ended.
        public var date: Date
        /// How long it lasted.
        public var seconds: TimeInterval
        /// Joules used by each app, keyed by ``AppIdentity/key``.
        public var joules: [String: Double]
        /// The whole Mac's power draw when the sample was taken, if known.
        public var systemWatts: Double?

        public init(date: Date, seconds: TimeInterval, joules: [String: Double], systemWatts: Double?) {
            self.date = date
            self.seconds = seconds
            self.joules = joules
            self.systemWatts = systemWatts
        }

        public var start: Date { date.addingTimeInterval(-seconds) }
    }

    /// An app as history remembers it, which outlives its process.
    public struct AppIdentity: Codable, Sendable, Equatable, Hashable {
        public var name: String
        public var bundleIdentifier: String?

        public init(name: String, bundleIdentifier: String?) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
        }

        /// Stable across launches: the bundle identifier, or the name for apps without one.
        public var key: String { bundleIdentifier ?? "name:" + name }
    }

    /// One app's share of the energy used over a period.
    public struct AppEnergy: Sendable, Equatable, Identifiable {
        public let app: AppIdentity
        public let joules: Double
        /// The battery time this energy is worth at the Mac's average power draw; `nil` without power readings.
        public let batteryTime: TimeInterval?

        public var id: String { app.key }
    }

    /// The Mac's time on battery since it was last unplugged.
    public struct BatteryStretch: Sendable, Equatable {
        public let since: Date
        public let duration: TimeInterval
        /// Percentage points used since then.
        public let used: Int
        /// The average drain, in percentage points an hour; `nil` until there's enough to go on.
        public let perHour: Double?
    }

    public static let retention: TimeInterval = 24 * 3600
    /// Samples keep this many apps each; the rest are too small to show.
    public static let appsPerSample = 15

    public private(set) var levels: [LevelPoint] = []
    public private(set) var samples: [EnergySample] = []
    public private(set) var apps: [String: AppIdentity] = [:]
    /// Where the latest stretch on battery began.
    public private(set) var unplugged: LevelPoint?

    public init() {}

    public var isEmpty: Bool { levels.isEmpty && samples.isEmpty }

    // MARK: - Recording

    /// Records the battery's level. Readings that change nothing are skipped, so this can be called freely.
    public mutating func record(_ snapshot: BatterySnapshot, at date: Date = Date()) {
        guard snapshot.hasBattery else { return }
        let point = LevelPoint(date: date, percentage: snapshot.percentage, isPluggedIn: snapshot.isPluggedIn)
        if let last = levels.last {
            guard date >= last.date else { return }
            if last.percentage == point.percentage, last.isPluggedIn == point.isPluggedIn { return }
            if last.isPluggedIn, !point.isPluggedIn {
                unplugged = point
            } else if !point.isPluggedIn, point.percentage > last.percentage + 1 {
                // Higher than before without being plugged in: it charged while we weren't running, at a time we don't know.
                unplugged = nil
            }
        }
        // On battery with nothing before it (the first launch, say), when it was unplugged is unknown.
        if point.isPluggedIn { unplugged = nil }
        levels.append(point)
        trim(now: date)
    }

    /// Records the energy apps used over a stretch on battery. Only the hungriest ``appsPerSample`` are kept.
    public mutating func record(
        joules: [AppIdentity: Double], seconds: TimeInterval, systemWatts: Double?, at date: Date = Date()
    ) {
        guard seconds > 0 else { return }
        var kept: [String: Double] = [:]
        kept.reserveCapacity(min(joules.count, Self.appsPerSample))
        for (app, value) in joules.sorted(by: { $0.value > $1.value }).prefix(Self.appsPerSample) where value > 0 {
            kept[app.key, default: 0] += value
            apps[app.key] = app
        }
        let sample = EnergySample(date: date, seconds: seconds, joules: kept, systemWatts: systemWatts)
        if let last = samples.last, date < last.date {
            // The clock went back. Keep the samples in date order, which reading them relies on.
            samples.insert(sample, at: Self.partitionIndex(in: samples) { $0.date <= date })
        } else {
            samples.append(sample)
        }
        trim(now: date)
    }

    /// Forgets everything.
    public mutating func removeAll() {
        self = BatteryHistory()
    }

    /// Drops what's older than ``retention``, keeping one level reading from before so the chart starts at its edge.
    ///
    /// It runs on every recording, so the usual case (nothing old enough to drop) costs two comparisons. Readings
    /// are kept in date order, so what's old is always at the front.
    public mutating func trim(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        // One reading from before the cutoff stays, as the level the chart starts from.
        if levels.count > 1, levels[1].date < cutoff {
            let firstKept = Self.firstIndex(in: levels, from: cutoff)
            levels.removeFirst(firstKept - 1)
        }
        guard let oldest = samples.first, oldest.date < cutoff else { return }
        samples.removeFirst(Self.partitionIndex(in: samples) { $0.date < cutoff })
        // Only samples name apps, so only dropping samples can leave one unused.
        pruneApps()
    }

    /// The index of the first element that isn't `isBefore` the point looked for, in an array in date order. A
    /// binary search: the history is read every time the panel draws, and holds a day of readings.
    static func partitionIndex<Element>(in elements: [Element], isBefore: (Element) -> Bool) -> Int {
        var low = elements.startIndex
        var high = elements.endIndex
        while low < high {
            let middle = low + (high - low) / 2
            if isBefore(elements[middle]) { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The first level reading at `date` or later.
    static func firstIndex(in levels: [LevelPoint], from date: Date) -> Int {
        partitionIndex(in: levels) { $0.date < date }
    }

    /// The first sample that ends after `date`: one that ends exactly then covers nothing after it.
    private func firstSample(after date: Date) -> Int {
        Self.partitionIndex(in: samples) { $0.date <= date }
    }

    /// Forgets apps no sample names any more.
    private mutating func pruneApps() {
        var used = Set<String>(minimumCapacity: apps.count)
        for sample in samples { used.formUnion(sample.joules.keys) }
        if apps.count > used.count { apps = apps.filter { used.contains($0.key) } }
    }

    // MARK: - Reading

    /// Level readings from `start` on, beginning with the level at `start` itself when it's known.
    public func levels(since start: Date) -> [LevelPoint] {
        let firstInside = Self.firstIndex(in: levels, from: start)
        guard firstInside < levels.endIndex else {
            // Nothing changed since: the last reading still holds.
            return levels.last.map { [LevelPoint(date: start, percentage: $0.percentage, isPluggedIn: $0.isPluggedIn)] } ?? []
        }
        var points: [LevelPoint] = []
        points.reserveCapacity(levels.count - firstInside + 1)
        if firstInside > 0 {
            let before = levels[firstInside - 1]
            points.append(LevelPoint(date: start, percentage: before.percentage, isPluggedIn: before.isPluggedIn))
        }
        points.append(contentsOf: levels[firstInside...])
        return points
    }

    /// A slice of time in the level chart: one bar.
    public struct LevelBucket: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        /// The level at the end of the slice; `nil` before history begins.
        public let percentage: Int?
        /// Plugged in at any point during the slice.
        public let isPluggedIn: Bool

        public var id: Date { start }
    }

    /// The last day in `count` equal slices ending at `now`, for a bar chart
    /// like iPhone's. A slice without readings of its own carries on the
    /// level before it, since levels are only recorded when they change.
    /// `current`, when given, is the level right now, for the last slice.
    public func levelBuckets(endingAt now: Date = Date(), count: Int = 48, current: BatterySnapshot? = nil) -> [LevelBucket] {
        guard count > 0 else { return [] }
        let length = Self.retention / Double(count)
        let start = now.addingTimeInterval(-Self.retention)
        var buckets: [LevelBucket] = []
        buckets.reserveCapacity(count)
        // The reading in effect when each slice starts, carried along as we go.
        var index = Self.firstIndex(in: levels, from: start)
        var carried: LevelPoint? = index > levels.startIndex ? levels[index - 1] : nil
        for slot in 0..<count {
            let bucketStart = start.addingTimeInterval(Double(slot) * length)
            let bucketEnd = slot == count - 1 ? now : bucketStart.addingTimeInterval(length)
            var pluggedIn = carried?.isPluggedIn ?? false
            while index < levels.endIndex, levels[index].date < bucketEnd {
                carried = levels[index]
                pluggedIn = pluggedIn || levels[index].isPluggedIn
                index += 1
            }
            var percentage = carried?.percentage
            if slot == count - 1, let current, current.hasBattery, carried != nil {
                percentage = current.percentage
                pluggedIn = pluggedIn || current.isPluggedIn
            }
            buckets.append(LevelBucket(start: bucketStart, end: bucketEnd, percentage: percentage, isPluggedIn: percentage != nil && pluggedIn))
        }
        return buckets
    }

    /// The stretches of time the Mac was plugged in, between `start` and `now`.
    public func pluggedInPeriods(since start: Date, now: Date = Date()) -> [DateInterval] {
        var periods: [DateInterval] = []
        var began: Date?
        for point in levels(since: start) {
            if point.isPluggedIn, began == nil {
                began = point.date
            } else if !point.isPluggedIn, let start = began {
                periods.append(DateInterval(start: start, end: point.date))
                began = nil
            }
        }
        if let began, now > began { periods.append(DateInterval(start: began, end: now)) }
        return periods
    }

    /// How long the Mac has been on battery since it was unplugged, and how fast it's draining.
    /// `nil` while plugged in, or when history doesn't know when it was unplugged.
    public func sinceUnplugged(_ snapshot: BatterySnapshot, now: Date = Date()) -> BatteryStretch? {
        guard snapshot.hasBattery, !snapshot.isPluggedIn, let unplugged, now > unplugged.date else { return nil }
        let duration = now.timeIntervalSince(unplugged.date)
        let used = max(unplugged.percentage - snapshot.percentage, 0)
        // A few minutes and a percent or two say little about the rate.
        let perHour = duration >= 15 * 60 && used >= 2 ? Double(used) / (duration / 3600) : nil
        return BatteryStretch(since: unplugged.date, duration: duration, used: used, perHour: perHour)
    }

    /// The apps that used the most energy from `start` on, most first.
    public func appEnergy(since start: Date) -> [AppEnergy] {
        let inRange = samples[firstSample(after: start)...]
        var totals: [String: Double] = [:]
        totals.reserveCapacity(apps.count)
        var wattsTotal = 0.0
        var wattsCount = 0
        for sample in inRange {
            // A sample that began before `start` counts for the part inside it.
            let fraction = sample.start < start ? max(sample.date.timeIntervalSince(start), 0) / sample.seconds : 1
            for (key, joules) in sample.joules { totals[key, default: 0] += joules * fraction }
            if let watts = sample.systemWatts, watts > 0 {
                wattsTotal += watts
                wattsCount += 1
            }
        }
        let averageWatts = wattsCount > 0 ? wattsTotal / Double(wattsCount) : nil
        var energy: [AppEnergy] = []
        energy.reserveCapacity(totals.count)
        for (key, joules) in totals {
            guard let app = apps[key] else { continue }
            energy.append(AppEnergy(app: app, joules: joules, batteryTime: averageWatts.map { joules / $0 }))
        }
        // Ties broken by key, so the order is the same every time the panel draws.
        return energy.sorted { $0.joules != $1.joules ? $0.joules > $1.joules : $0.id < $1.id }
    }

    /// How much time on battery the energy samples since `start` cover.
    public func sampledTime(since start: Date) -> TimeInterval {
        samples[firstSample(after: start)...].reduce(0) { $0 + min($1.seconds, $1.date.timeIntervalSince(start)) }
    }
}

extension BatteryHistory {
    /// Reads history saved with ``save(to:)``; empty when there's none, or it can't be read.
    public static func load(from url: URL) -> BatteryHistory {
        guard let data = try? Data(contentsOf: url),
            let file = try? PropertyListDecoder().decode(File.self, from: data),
            file.version == File.currentVersion
        else { return BatteryHistory() }
        var history = file.history
        history.trim()
        history.pruneApps()
        return history
    }

    /// Saves to disk, as a compact binary property list, replacing the file in one go.
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(File(version: File.currentVersion, history: self)).write(to: url, options: .atomic)
    }

    /// What's on disk, versioned so a future format can tell an old file from its own.
    private struct File: Codable {
        static let currentVersion = 1
        var version: Int
        var history: BatteryHistory
    }
}
