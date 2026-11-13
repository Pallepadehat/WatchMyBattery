import Foundation

/// Decides when the battery has charged to the level you unplug at, for people who keep it from charging all the way
/// by hand rather than with a charge limit.
///
/// It fires once per charge, as the level reaches the target while plugged in. Unplugging re-arms it. Plugging in
/// already at or above the target says nothing: there's nothing to wait for.
public struct ChargeLevelAlert: Sendable, Equatable {
    /// Notified for this charge already, or plugged in at or above the target.
    public private(set) var isSpent = false
    private var wasPluggedIn = false

    public init() {}

    /// Feeds in a new reading; returns `true` when the target was just reached.
    public mutating func update(with snapshot: BatterySnapshot, target: Int) -> Bool {
        defer { wasPluggedIn = snapshot.hasBattery && snapshot.isPluggedIn }
        guard snapshot.hasBattery, snapshot.isPluggedIn else {
            isSpent = false
            return false
        }
        // Just plugged in: only a charge that has yet to reach the target is worth a word.
        if !wasPluggedIn {
            isSpent = snapshot.percentage >= target
            return false
        }
        guard !isSpent, snapshot.percentage >= target else { return false }
        isSpent = true
        return true
    }
}
