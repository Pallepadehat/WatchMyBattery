import Foundation

/// One stretch of the Mac asleep: when it went to sleep and woke, and the battery either side.
public struct SleepSession: Codable, Sendable, Equatable, Identifiable {
    public var start: Date
    public var end: Date
    /// Charge level going to sleep, 0–100.
    public var startLevel: Int
    /// Charge level on waking, 0–100.
    public var endLevel: Int
    /// On the adapter at either end: what it used then can't be told from the level.
    public var wasPluggedIn: Bool

    public init(start: Date, end: Date, startLevel: Int, endLevel: Int, wasPluggedIn: Bool) {
        self.start = start
        self.end = end
        self.startLevel = min(max(startLevel, 0), 100)
        self.endLevel = min(max(endLevel, 0), 100)
        self.wasPluggedIn = wasPluggedIn
    }

    public var id: Date { start }
    public var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }

    /// Percent of battery used while asleep; `nil` on the adapter, where charging hides it.
    public var used: Int? { wasPluggedIn ? nil : max(startLevel - endLevel, 0) }

    /// Percent used per hour asleep; `nil` on the adapter, or when it slept too briefly to say.
    public var perHour: Double? {
        guard let used, duration >= SleepLog.shortestMeaningful else { return nil }
        return Double(used) / (duration / 3600)
    }

    /// How it compares with a healthy sleep. A Mac asleep on battery should lose about 1% an hour at most; more than
    /// that usually means something kept waking it (a Bluetooth device, network access, an app asking for time).
    public var drain: SleepDrain {
        guard let perHour else { return .unknown }
        if perHour <= SleepDrain.normalPerHour { return .normal }
        if perHour <= SleepDrain.heavyPerHour { return .elevated }
        return .heavy
    }
}

/// How quickly a sleep used the battery.
public enum SleepDrain: Sendable, Equatable, Comparable {
    case unknown
    case normal
    case elevated
    case heavy

    /// About what a modern MacBook loses asleep with nothing waking it, give or take.
    public static let normalPerHour = 1.0
    /// Clearly more than it should: worth saying so.
    public static let heavyPerHour = 2.5
}

/// The last few weeks of sleeps, newest last, kept as a small file.
///
/// WatchMyBattery hears from macOS as the Mac goes to sleep and as it wakes (and reads the battery at both
/// moments), so recording a sleep costs nothing and needs no polling. `pmset -g log` has the same story in more
/// detail, but reading it takes seconds of CPU time, too much to do on every wake.
public struct SleepLog: Codable, Sendable, Equatable {
    public private(set) var sessions: [SleepSession] = []

    /// Sleeps older than this are let go.
    public static let retention: TimeInterval = 30 * 24 * 3600
    /// Shorter sleeps (a lid closed for a moment) aren't worth keeping.
    public static let shortestKept: TimeInterval = 60
    /// Below this, a percent or two either way says nothing about the rate.
    public static let shortestMeaningful: TimeInterval = 30 * 60

    public init(sessions: [SleepSession] = []) {
        self.sessions = sessions.sorted { $0.start < $1.start }
    }

    public var isEmpty: Bool { sessions.isEmpty }
    public var last: SleepSession? { sessions.last }

    /// Adds a sleep that just ended, unless it was too short to matter. Returns whether it was kept.
    @discardableResult
    public mutating func record(_ session: SleepSession, now: Date = Date()) -> Bool {
        defer { trim(now: now) }
        guard session.duration >= Self.shortestKept else { return false }
        // The same sleep reported twice (a wake notification repeated) replaces the first.
        sessions.removeAll { $0.start == session.start }
        let index = sessions.firstIndex { $0.start > session.start } ?? sessions.endIndex
        sessions.insert(session, at: index)
        return true
    }

    public mutating func removeAll() {
        sessions = []
    }

    public mutating func trim(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        sessions.removeAll { $0.end < cutoff }
    }

    /// The typical rate on battery, from the sleeps that say something: the median, so one bad night doesn't skew it.
    public var typicalPerHour: Double? {
        let rates = sessions.compactMap(\.perHour).sorted()
        guard rates.count >= 3 else { return nil }
        let middle = rates.count / 2
        return rates.count.isMultiple(of: 2) ? (rates[middle - 1] + rates[middle]) / 2 : rates[middle]
    }

    /// The sleeps on battery since `start`, newest first, for a list.
    public func recent(since start: Date) -> [SleepSession] {
        sessions.filter { $0.end >= start }.reversed()
    }

    // MARK: - On disk

    public static func load(from url: URL) -> SleepLog {
        guard let data = try? Data(contentsOf: url), let log = try? JSONDecoder().decode(SleepLog.self, from: data) else {
            return SleepLog()
        }
        return log
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
