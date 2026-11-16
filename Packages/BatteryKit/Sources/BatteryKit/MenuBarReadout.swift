import Foundation

/// The text the menu bar can show next to the icon.
public enum MenuBarLabel: String, CaseIterable, Identifiable, Sendable {
    case none
    case percentage
    /// Time until empty on battery, or until full while charging.
    case timeRemaining
    /// The whole Mac's power draw, in watts.
    case powerDraw

    public var id: Self { self }
}

/// What the menu bar's text says right now, for a ``MenuBarLabel``.
///
/// When the chosen number doesn't apply (no time left while the battery is full, no power reading yet), it falls back
/// to the percentage rather than leave a gap or a placeholder in the menu bar.
public enum MenuBarReadout: Sendable, Equatable {
    case percentage(Int)
    case time(TimeInterval)
    case watts(Double)

    public init?(label: MenuBarLabel, snapshot: BatterySnapshot, watts: Double?) {
        let percentage: MenuBarReadout? = snapshot.hasBattery ? .percentage(snapshot.percentage) : nil
        switch label {
        case .none:
            return nil
        case .percentage:
            guard let percentage else { return nil }
            self = percentage
        case .timeRemaining:
            let counting = snapshot.chargeState == .discharging || snapshot.chargeState == .charging
            if counting, let time = snapshot.timeRemaining {
                self = .time(time)
            } else if let percentage {
                self = percentage
            } else {
                return nil
            }
        case .powerDraw:
            if let watts, watts.isFinite, watts >= 0 {
                self = .watts(watts)
            } else if let percentage {
                self = percentage
            } else {
                return nil
            }
        }
    }
}

/// Formats power for people: no more precision than a reading that moves by the second deserves.
public enum PowerFormat {
    /// `4.2 W` under ten watts, `12 W` from there up.
    public static func watts(_ watts: Double, locale: Locale = .current) -> String {
        let value = max(watts, 0)
        let digits = value < 9.95 ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " W"
    }
}
