import Foundation

/// "7 hr, 12 min" style durations in words, for sleeps and other stretches people read rather than glance at.
enum DurationText {
    /// "7h 12m", or "45m": short, for the panel.
    static func short(_ interval: TimeInterval) -> String {
        format(interval, style: .abbreviated)
    }

    /// "7 hours, 12 minutes", for VoiceOver and notifications.
    static func spoken(_ interval: TimeInterval) -> String {
        format(interval, style: .full)
    }

    private static func format(_ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        // Rounded to the minute: seconds would only add noise.
        return formatter.string(from: max((interval / 60).rounded() * 60, 60)) ?? ""
    }
}
