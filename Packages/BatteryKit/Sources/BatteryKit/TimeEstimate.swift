import Foundation

/// The arithmetic behind "quit this app and get 48 minutes back".
public enum TimeEstimate {
    /// How much longer the battery would last without a consumer drawing
    /// `appWatts` out of a system total of `systemWatts`.
    ///
    /// With the same charge left, time scales inversely with power:
    /// `t' = t × P / (P − p)`, so the time gained is `t × p / (P − p)`.
    /// The app's share is capped, because the screen and the rest of the Mac
    /// keep drawing power whatever you quit.
    public static func timeGained(timeRemaining: TimeInterval, systemWatts: Double, appWatts: Double) -> TimeInterval {
        guard timeRemaining > 0, systemWatts > 0, appWatts > 0 else { return 0 }
        let share = min(appWatts / systemWatts, maximumShare)
        return timeRemaining * share / (1 - share)
    }

    /// No app can claim more than this share of the system's power draw.
    public static let maximumShare = 0.8
}
