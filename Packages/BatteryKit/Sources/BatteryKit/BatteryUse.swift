import Foundation

/// How much of the battery an amount of energy is: "Safari used 6% of the battery", which reads at a glance where
/// joules, or the battery time they'd be worth, don't.
///
/// Worked out from this Mac's own history rather than a battery's rated capacity: over the hours measured on battery,
/// how many percentage points went for each joule the whole Mac used. That takes in the battery's size and its wear
/// alike, and needs nothing more than the history already keeps.
extension UsageProfile {
    /// Percentage points of the battery per joule, from the hours measured on battery; `nil` until there's enough to
    /// go on (a few points used over half an hour measured), or without power readings.
    ///
    /// Each hour counts for the part of it that was measured: an hour mostly asleep, measured for five minutes,
    /// gives five minutes' worth of its drain, so time asleep doesn't make the Mac's draw look higher than it was.
    public var pointsPerJoule: Double? {
        var points = 0.0
        var joules = 0.0
        var measured = 0.0
        for hour in hours where hour.measuredSeconds > 0 && hour.systemJoules > 0 && hour.batterySeconds > 0 {
            let weight = min(hour.measuredSeconds / hour.batterySeconds, 1)
            points += Double(hour.drained) * weight
            joules += hour.systemJoules
            measured += hour.measuredSeconds
        }
        guard points >= Self.minimumPointsForRate, measured >= Self.minimumMeasuredForRate, joules > 0 else { return nil }
        return min(max(points / joules, Self.plausibleRate.lowerBound), Self.plausibleRate.upperBound)
    }

    /// Fewer points than this is mostly rounding: the level only moves a whole percent at a time.
    static let minimumPointsForRate = 3.0
    static let minimumMeasuredForRate: TimeInterval = 30 * 60
    /// From a 150 Wh battery (the biggest a MacBook has had, with room) to a 30 Wh one (a worn 12-inch MacBook): a
    /// rate outside that is a measuring problem, not a battery.
    static let plausibleRate = (100 / (150 * 3600.0))...(100 / (30 * 3600.0))
}

/// Energy as a share of the battery.
public enum BatteryUse {
    /// Percentage points of the battery `joules` is, at `rate` (see ``UsageProfile/pointsPerJoule``); `nil` without
    /// a rate.
    public static func points(joules: Double, rate: Double?) -> Double? {
        guard let rate, joules.isFinite, joules >= 0 else { return nil }
        return joules * rate
    }
}
