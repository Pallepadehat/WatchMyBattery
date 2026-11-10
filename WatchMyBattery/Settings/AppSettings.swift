import Foundation
import Observation

/// Where the menu bar shows the charge percentage.
enum PercentageStyle: String, CaseIterable, Identifiable {
    case hidden
    case inside
    case beside

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .hidden: "Hidden"
        case .inside: "Inside the battery"
        case .beside: "Next to the battery"
        }
    }
}

/// What the middle of the panel's big battery shows.
enum CenterLabel: String, CaseIterable, Identifiable {
    case timeRemaining
    case percentage

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .timeRemaining: "Time remaining"
        case .percentage: "Percentage"
        }
    }
}

/// The user's preferences, saved in `UserDefaults` as they change.
@Observable
final class AppSettings {
    var percentageStyle: PercentageStyle {
        didSet { defaults.set(percentageStyle.rawValue, forKey: Key.percentageStyle) }
    }

    /// Green while charging, yellow in Low Power Mode, red when low, instead of a monochrome icon.
    var usesColor: Bool {
        didSet { defaults.set(usesColor, forKey: Key.usesColor) }
    }

    var centerLabel: CenterLabel {
        didSet { defaults.set(centerLabel.rawValue, forKey: Key.centerLabel) }
    }

    /// How many apps get a slice of the battery.
    var maximumApps: Int {
        didSet { defaults.set(maximumApps, forKey: Key.maximumApps) }
    }

    /// Ask before quitting an app that was dragged out of the panel.
    var confirmsQuit: Bool {
        didSet { defaults.set(confirmsQuit, forKey: Key.confirmsQuit) }
    }

    /// The tip about hiding the built-in battery icon, until it's dismissed.
    var showsReplaceTip: Bool {
        didSet { defaults.set(showsReplaceTip, forKey: Key.showsReplaceTip) }
    }

    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }

    static let appCountRange = 2...6

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.percentageStyle: PercentageStyle.hidden.rawValue,
            Key.usesColor: true,
            Key.centerLabel: CenterLabel.timeRemaining.rawValue,
            Key.maximumApps: 4,
            Key.confirmsQuit: false,
            Key.showsReplaceTip: true,
            Key.hasSeenWelcome: false,
        ])
        percentageStyle = PercentageStyle(rawValue: defaults.string(forKey: Key.percentageStyle) ?? "") ?? .hidden
        usesColor = defaults.bool(forKey: Key.usesColor)
        centerLabel = CenterLabel(rawValue: defaults.string(forKey: Key.centerLabel) ?? "") ?? .timeRemaining
        maximumApps = min(max(defaults.integer(forKey: Key.maximumApps), Self.appCountRange.lowerBound), Self.appCountRange.upperBound)
        confirmsQuit = defaults.bool(forKey: Key.confirmsQuit)
        showsReplaceTip = defaults.bool(forKey: Key.showsReplaceTip)
        hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)
    }

    private enum Key {
        static let percentageStyle = "percentageStyle"
        static let usesColor = "usesColor"
        static let centerLabel = "centerLabel"
        static let maximumApps = "maximumApps"
        static let confirmsQuit = "confirmsQuit"
        static let showsReplaceTip = "showsReplaceTip"
        static let hasSeenWelcome = "hasSeenWelcome"
    }
}
