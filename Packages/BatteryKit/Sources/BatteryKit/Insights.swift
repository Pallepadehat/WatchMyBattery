import Foundation

// Things worth acting on, worked out from what WatchMyBattery already measures. Each check says nothing rather than
// guess: without enough history to back a claim, it returns `nil` or nothing.

// MARK: - Charge before a meeting

/// When something on the calendar starts and ends. Nothing else about it is read.
public struct UpcomingEvent: Sendable, Equatable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(end, start)
    }
}

/// The battery is expected to run out before a meeting is over.
public struct MeetingWarning: Sendable, Equatable {
    public enum Timing: Sendable, Equatable {
        /// It runs out before the meeting starts.
        case beforeStart
        /// It lasts until the meeting starts, but not to its end.
        case duringMeeting
    }

    public let event: UpcomingEvent
    /// When the battery is expected to run out, rounded down to five minutes so it doesn't promise more than it knows.
    public let runsOutAt: Date
    public let timing: Timing

    /// Already under way.
    public func hasStarted(now: Date) -> Bool { event.start <= now }
}

public enum MeetingCheck {
    /// How far ahead a warning can be asked for, in minutes.
    public static let leadChoices = [15, 30, 45, 60, 90, 120]
    public static let defaultLead = 30

    /// The first meeting starting within `lead` (or under way) that the battery won't last through, at the current
    /// estimate. `nil` on the adapter, or while macOS is still working out the time left.
    ///
    /// `margin` counts a battery that runs out that soon after the meeting as not lasting either. Once a warning is
    /// shown, the app checks with a margin, so it doesn't come and go as macOS's estimate moves by a few minutes.
    public static func warning(
        snapshot: BatterySnapshot, events: [UpcomingEvent], now: Date = Date(), lead: TimeInterval, margin: TimeInterval = 0
    ) -> MeetingWarning? {
        guard snapshot.hasBattery, snapshot.chargeState == .discharging, let remaining = snapshot.timeRemaining, remaining > 0 else {
            return nil
        }
        let runsOut = now.addingTimeInterval(remaining)
        let horizon = now.addingTimeInterval(lead)
        for event in events.sorted(by: { $0.start < $1.start }) where event.end > now && event.start <= horizon {
            guard runsOut < event.end.addingTimeInterval(margin) else { continue }
            let timing: MeetingWarning.Timing = runsOut < event.start ? .beforeStart : .duringMeeting
            return MeetingWarning(event: event, runsOutAt: roundedDown(runsOut), timing: timing)
        }
        return nil
    }

    /// When a warning could next become due, if nothing else changes: the next meeting coming within `lead`. The app
    /// checks again then, rather than every few minutes.
    public static func nextCheck(events: [UpcomingEvent], now: Date = Date(), lead: TimeInterval) -> Date? {
        events.map { $0.start.addingTimeInterval(-lead) }.filter { $0 > now }.min()
    }

    static func roundedDown(_ date: Date, to step: TimeInterval = 5 * 60) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded(.down) * step)
    }
}

// MARK: - More than usual

/// The Mac is drawing clearly more power than it usually does at this time of day.
public struct UnusualDrain: Sendable, Equatable {
    public let currentWatts: Double
    public let usualWatts: Double
    /// The app that accounts for most of the difference, if one does.
    public let cause: BatteryHistory.AppIdentity?

    public init(currentWatts: Double, usualWatts: Double, cause: BatteryHistory.AppIdentity?) {
        self.currentWatts = currentWatts
        self.usualWatts = usualWatts
        self.cause = cause
    }

    public var ratio: Double { currentWatts / usualWatts }

    /// How much more, rounded to ten percent: the readings aren't precise enough for more. `nil` from twice as much,
    /// which ``timesAsMuch`` says better.
    public var percentMore: Int? {
        guard ratio < 1.95 else { return nil }
        return max(Int(((ratio - 1) * 10).rounded()) * 10, 10)
    }

    /// "About three times as much", rounded to a whole number.
    public var timesAsMuch: Int { Int(ratio.rounded()) }
}

public enum UsualDrainCheck {
    /// The current draw is the average over this much of the latest samples.
    public static let window: TimeInterval = 45 * 60
    /// How many earlier days need readings around this time before anything is called usual.
    public static let daysNeeded = 5
    /// More than this, and by more than ``minimumDifference``, is worth saying.
    public static let ratioThreshold = 1.2
    public static let minimumDifference = 1.0

    /// Compares the last ``window`` with the same time of day (give or take an hour) on earlier days.
    public static func check(history: BatteryHistory, profile: UsageProfile, now: Date = Date(), calendar: Calendar = .current) -> UnusualDrain? {
        guard let current = currentDraw(history: history, now: now),
            let usual = usualDraw(profile: profile, now: now, calendar: calendar)
        else { return nil }
        guard current.watts >= usual.watts * ratioThreshold, current.watts - usual.watts >= minimumDifference else { return nil }

        // The app whose draw grew the most, if it explains at least half of the difference.
        let difference = current.watts - usual.watts
        var grew: (key: String, extra: Double)?
        for (key, watts) in current.apps {
            let extra = watts - (usual.apps[key] ?? 0)
            // Ties go to the key that sorts first, so the answer is the same every time.
            if let best = grew, extra < best.extra || (extra == best.extra && key > best.key) { continue }
            grew = (key, extra)
        }
        var cause: BatteryHistory.AppIdentity?
        if let grew, grew.extra >= difference / 2 { cause = history.apps[grew.key] }
        return UnusualDrain(currentWatts: current.watts, usualWatts: usual.watts, cause: cause)
    }

    /// The average draw of the Mac and each app over the last ``window``; `nil` without enough recent samples.
    static func currentDraw(history: BatteryHistory, now: Date) -> (watts: Double, apps: [String: Double])? {
        let start = now.addingTimeInterval(-window)
        // A sample spanning sleep (the first after waking) has one power reading for hours: it can't speak for the
        // last few minutes.
        let recent = history.samples.filter { $0.date > start && $0.date <= now && $0.seconds <= UsageProfile.longestMeasuredSample }
        // The latest sample has to be recent: the Mac has to be on battery now, not an hour ago.
        guard let latest = recent.last, now.timeIntervalSince(latest.date) <= 10 * 60 else { return nil }
        var joules = 0.0
        var measured = 0.0
        var sampled = 0.0
        var apps: [String: Double] = [:]
        for sample in recent {
            sampled += sample.seconds
            for (key, value) in sample.joules { apps[key, default: 0] += value }
            if let watts = sample.systemWatts, watts > 0 {
                joules += watts * sample.seconds
                measured += sample.seconds
            }
        }
        guard measured >= window * 0.55, sampled > 0 else { return nil }
        return (joules / measured, apps.mapValues { $0 / sampled })
    }

    /// The average draw of the Mac and each app around this time of day on earlier days; `nil` until there are
    /// ``daysNeeded`` of them.
    static func usualDraw(profile: UsageProfile, now: Date, calendar: Calendar) -> (watts: Double, apps: [String: Double])? {
        let today = calendar.startOfDay(for: now)
        let hourNow = calendar.component(.hour, from: now)
        var joules = 0.0
        var measured = 0.0
        var sampled = 0.0
        var apps: [String: Double] = [:]
        var perDay: [Date: Double] = [:]
        for hour in profile.hours where hour.start < today && hour.measuredSeconds > 0 {
            let distance = abs(calendar.component(.hour, from: hour.start) - hourNow)
            guard min(distance, 24 - distance) <= 1 else { continue }
            joules += hour.systemJoules
            measured += hour.measuredSeconds
            sampled += hour.sampledSeconds
            for (key, value) in hour.appJoules { apps[key, default: 0] += value }
            perDay[calendar.startOfDay(for: hour.start), default: 0] += hour.measuredSeconds
        }
        // A day counts once it has a reasonable stretch measured around this time.
        guard perDay.values.filter({ $0 >= 15 * 60 }).count >= daysNeeded, measured > 0, sampled > 0 else { return nil }
        return (joules / measured, apps.mapValues { $0 / sampled })
    }
}

// MARK: - A new app

public enum NewAppCheck {
    /// An app first seen this recently is new.
    public static let newFor: TimeInterval = 3 * 24 * 3600
    /// Only once history goes back this far: before that, every app looks new.
    public static let historyNeeded: TimeInterval = 7 * 24 * 3600
    /// "A lot": at least this share of all the energy apps used over the last day…
    public static let minimumShare = 0.2
    /// …and at least this much energy (a watt for an hour).
    public static let minimumJoules = 3600.0

    /// Apps that are new and among the three hungriest of the last 24 hours, hungriest first.
    public static func newApps(history: BatteryHistory, profile: UsageProfile, now: Date = Date()) -> [BatteryHistory.AppEnergy] {
        guard let oldest = profile.hours.first, oldest.start <= now.addingTimeInterval(-historyNeeded), profile.measuredDays().count >= 4 else {
            return []
        }
        let apps = history.appEnergy(since: now.addingTimeInterval(-BatteryHistory.retention))
        let total = apps.reduce(0) { $0 + $1.joules }
        guard total > 0 else { return [] }
        return apps.prefix(3).filter { app in
            guard let seen = profile.apps[app.id] else { return false }
            return seen.firstSeen >= now.addingTimeInterval(-newFor) && app.joules >= minimumJoules && app.joules / total >= minimumShare
        }
    }
}
