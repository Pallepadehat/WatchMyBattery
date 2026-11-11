import Foundation

/// Turns power readings into the times the panel shows.
public struct Estimates: Sendable, Equatable {
    public let snapshot: BatterySnapshot
    public let systemWatts: Double?

    public init(snapshot: BatterySnapshot, systemWatts: Double?) {
        self.snapshot = snapshot
        self.systemWatts = systemWatts
    }

    /// Time estimates only make sense while running on battery.
    public var appliesToTime: Bool {
        snapshot.chargeState == .discharging && snapshot.timeRemaining != nil && systemWatts != nil
    }

    /// The share of the system's power draw an app is responsible for, 0–1.
    public func share(of watts: Double) -> Double {
        guard let systemWatts, systemWatts > 0 else { return 0 }
        return min(watts / systemWatts, TimeEstimate.maximumShare)
    }

    /// How much battery time quitting apps that draw `watts` in total would give back.
    public func timeGained(byQuitting watts: Double) -> TimeInterval {
        guard appliesToTime, let timeRemaining = snapshot.timeRemaining, let systemWatts else { return 0 }
        return TimeEstimate.timeGained(timeRemaining: timeRemaining, systemWatts: systemWatts, appWatts: watts)
    }

    /// Each app's share of the panel's battery: its cost out of all the time
    /// there'd be without any of them. On the adapter, where time doesn't
    /// apply, its share of the power draw.
    public func sliceShares(forAppsDrawing watts: [Double]) -> [Double] {
        if appliesToTime, let timeRemaining = snapshot.timeRemaining {
            let costs = watts.map(timeGained(byQuitting:))
            let total = timeRemaining + costs.reduce(0, +)
            return costs.map { total > 0 ? $0 / total : 0 }
        }
        return watts.map(share(of:))
    }
}
