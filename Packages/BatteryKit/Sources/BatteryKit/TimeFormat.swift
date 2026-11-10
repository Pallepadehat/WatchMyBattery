import Foundation

/// Formats battery times the way the menu bar shows them.
public enum TimeFormat {
    /// `4:50`: hours and minutes, like the built-in battery menu.
    public static func clock(_ interval: TimeInterval) -> String {
        let minutes = totalMinutes(interval)
        return "\(minutes / 60):" + (minutes % 60 < 10 ? "0" : "") + "\(minutes % 60)"
    }

    /// `48m` under an hour, `1:10` from an hour up.
    public static func compact(_ interval: TimeInterval) -> String {
        let minutes = totalMinutes(interval)
        return minutes < 60 ? "\(minutes)m" : clock(interval)
    }

    /// `−48m` (with a real minus sign): time an app costs.
    public static func cost(_ interval: TimeInterval) -> String { "\u{2212}" + compact(interval) }

    /// `+1:10`: time you'd gain.
    public static func gain(_ interval: TimeInterval) -> String { "+" + compact(interval) }

    private static func totalMinutes(_ interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 0 }
        return Int((interval / 60).rounded())
    }
}
