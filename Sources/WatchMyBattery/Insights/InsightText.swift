import BatteryKit
import Foundation

/// What the insights say, the same in the panel and in their notifications.
enum InsightText {
    // MARK: Charge before a meeting

    static func meetingTitle(_ warning: MeetingWarning, now: Date = Date()) -> String {
        warning.hasStarted(now: now)
            ? String(localized: "Charge now to get through your meeting")
            : String(localized: "Charge before your \(time(warning.event.start)) meeting")
    }

    static func meetingDetail(_ warning: MeetingWarning) -> String {
        switch warning.timing {
        case .beforeStart:
            String(localized: "The battery should last until about \(time(warning.runsOutAt)).")
        case .duringMeeting:
            String(localized: "The battery should last until about \(time(warning.runsOutAt)), and the meeting runs until \(time(warning.event.end)).")
        }
    }

    // MARK: More than usual

    static let unusualDrainTitle = String(localized: "Using more power than usual")

    static func unusualDrainDetail(_ drain: UnusualDrain) -> String {
        let cause = drain.cause?.name
        if let percent = drain.percentMore {
            let more = (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
            return cause.map { String(localized: "About \(more) more than at this time on most days, mostly because of \($0).") }
                ?? String(localized: "About \(more) more than at this time on most days.")
        }
        let times = drain.timesAsMuch
        return cause.map { String(localized: "About \(times) times as much as at this time on most days, mostly because of \($0).") }
            ?? String(localized: "About \(times) times as much as at this time on most days.")
    }

    // MARK: A new app

    static func newAppTitle(_ app: BatteryHistory.AppIdentity) -> String {
        String(localized: "\(app.name) is new, and using a lot of battery")
    }

    static let newAppDetail = String(localized: "It hadn't used much battery in the last two weeks, and is now among the apps using the most.")

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
