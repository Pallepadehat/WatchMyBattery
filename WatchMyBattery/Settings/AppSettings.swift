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
        case .inside: "Inside"
        case .beside: "Beside"
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

    /// A gentle animation in the menu bar icon and the panel's battery while charging.
    var showsChargingAnimation: Bool {
        didSet { defaults.set(showsChargingAnimation, forKey: Key.showsChargingAnimation) }
    }

    /// Bundle identifiers of apps that never get a slice, so they can't be dragged out by accident.
    var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Key.excludedApps) }
    }

    /// Send a notification when the battery runs low.
    var notifiesWhenLow: Bool {
        didSet { defaults.set(notifiesWhenLow, forKey: Key.notifiesWhenLow) }
    }

    /// The percentages a low battery notification is sent at, highest first.
    var lowBatteryLevels: [Int] {
        didSet { defaults.set(lowBatteryLevels, forKey: Key.lowBatteryLevels) }
    }

    /// Keep a history of the battery level and the apps using it (measured every few minutes on battery).
    var recordsHistory: Bool {
        didSet { defaults.set(recordsHistory, forKey: Key.recordsHistory) }
    }

    /// The panel's history section is open.
    var showsHistory: Bool {
        didSet { defaults.set(showsHistory, forKey: Key.showsHistory) }
    }

    /// Send a notification when an app uses a lot of power for a while.
    var notifiesAboutRunawayApps: Bool {
        didSet { defaults.set(notifiesAboutRunawayApps, forKey: Key.notifiesAboutRunawayApps) }
    }

    /// The tip about hiding the built-in battery icon, until it's dismissed.
    var showsReplaceTip: Bool {
        didSet { defaults.set(showsReplaceTip, forKey: Key.showsReplaceTip) }
    }

    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }

    /// A key combination that opens and closes the panel from any app; `nil` for none.
    var panelShortcut: Hotkey? {
        didSet {
            if let data = panelShortcut.flatMap({ try? JSONEncoder().encode($0) }) {
                defaults.set(data, forKey: Key.panelShortcut)
            } else {
                defaults.removeObject(forKey: Key.panelShortcut)
            }
        }
    }

    static let appCountRange = 1...4
    /// Levels a low battery notification can be sent at.
    static let lowBatteryChoices = [5, 10, 15, 20, 25, 30]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.percentageStyle: PercentageStyle.hidden.rawValue,
            Key.usesColor: true,
            Key.centerLabel: CenterLabel.timeRemaining.rawValue,
            Key.maximumApps: 3,
            Key.confirmsQuit: false,
            Key.showsChargingAnimation: true,
            Key.excludedApps: [String](),
            Key.notifiesWhenLow: false,
            Key.lowBatteryLevels: [20, 10],
            Key.recordsHistory: true,
            Key.showsHistory: true,
            Key.notifiesAboutRunawayApps: false,
            Key.showsReplaceTip: true,
            Key.hasSeenWelcome: false,
        ])
        percentageStyle = PercentageStyle(rawValue: defaults.string(forKey: Key.percentageStyle) ?? "") ?? .hidden
        usesColor = defaults.bool(forKey: Key.usesColor)
        centerLabel = CenterLabel(rawValue: defaults.string(forKey: Key.centerLabel) ?? "") ?? .timeRemaining
        maximumApps = min(max(defaults.integer(forKey: Key.maximumApps), Self.appCountRange.lowerBound), Self.appCountRange.upperBound)
        confirmsQuit = defaults.bool(forKey: Key.confirmsQuit)
        showsChargingAnimation = defaults.bool(forKey: Key.showsChargingAnimation)
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? []
        notifiesWhenLow = defaults.bool(forKey: Key.notifiesWhenLow)
        lowBatteryLevels = ((defaults.array(forKey: Key.lowBatteryLevels) as? [Int]) ?? [20, 10])
            .filter(Self.lowBatteryChoices.contains).sorted(by: >)
        recordsHistory = defaults.bool(forKey: Key.recordsHistory)
        showsHistory = defaults.bool(forKey: Key.showsHistory)
        notifiesAboutRunawayApps = defaults.bool(forKey: Key.notifiesAboutRunawayApps)
        showsReplaceTip = defaults.bool(forKey: Key.showsReplaceTip)
        hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)
        panelShortcut = defaults.data(forKey: Key.panelShortcut).flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) }
    }

    /// Whether an app never gets a slice.
    func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedApps.contains(bundleIdentifier)
    }

    func exclude(bundleIdentifier: String) {
        guard !excludedApps.contains(bundleIdentifier) else { return }
        excludedApps.append(bundleIdentifier)
    }

    private enum Key {
        static let percentageStyle = "percentageStyle"
        static let usesColor = "usesColor"
        static let centerLabel = "centerLabel"
        static let maximumApps = "maximumApps"
        static let confirmsQuit = "confirmsQuit"
        static let showsChargingAnimation = "showsChargingAnimation"
        static let excludedApps = "excludedApps"
        static let notifiesWhenLow = "notifiesWhenLow"
        static let lowBatteryLevels = "lowBatteryLevels"
        static let recordsHistory = "recordsHistory"
        static let showsHistory = "showsHistory"
        static let notifiesAboutRunawayApps = "notifiesAboutRunawayApps"
        static let showsReplaceTip = "showsReplaceTip"
        static let hasSeenWelcome = "hasSeenWelcome"
        static let panelShortcut = "panelShortcut"
    }
}
