import Foundation

/// Decides when the battery has run low enough for a notification.
///
/// Each level fires once on the way down. Plugging in re-arms them all, so
/// the next time the battery drains you hear about it again.
public struct LowBatteryAlert: Sendable, Equatable {
    /// Levels already notified about since the Mac was last plugged in.
    public private(set) var notified: Set<Int> = []

    public init() {}

    /// Feeds in a new reading; returns the level to notify about, if one was just reached.
    public mutating func update(with snapshot: BatterySnapshot, levels: [Int]) -> Int? {
        guard snapshot.hasBattery, snapshot.chargeState == .discharging else {
            notified.removeAll()
            return nil
        }
        // The lowest level reached and not yet notified about. Several at once
        // (waking from sleep much lower, say) give one notification, for the lowest.
        let reached = levels.filter { snapshot.percentage <= $0 && !notified.contains($0) }
        guard let level = reached.min() else { return nil }
        notified.formUnion(reached)
        return level
    }
}
