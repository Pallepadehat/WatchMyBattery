import BatteryKit
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

/// Where the AirPods card slides in.
enum AccessoryCardPosition: String, CaseIterable, Identifiable {
    /// Under the battery in the menu bar, where the panel opens.
    case belowIcon
    case topCenter
    /// In the corner, where notifications appear.
    case topRight

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .belowIcon: "Below the Menu Bar Icon"
        case .topCenter: "Top Center"
        case .topRight: "Top Right"
        }
    }
}

/// How far back the panel's history looks.
enum HistoryRange: String, CaseIterable, Identifiable {
    case day
    case tenDays

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .day: "24 Hours"
        case .tenDays: "10 Days"
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

    /// The panel's history shows the last day, or the last ten.
    var historyRange: HistoryRange {
        didSet { defaults.set(historyRange.rawValue, forKey: Key.historyRange) }
    }

    /// Insights ("More than usual", a new app, a meeting) show in the panel.
    var showsInsights: Bool {
        didSet { defaults.set(showsInsights, forKey: Key.showsInsights) }
    }

    /// Warn when the battery won't last through the next meeting on the calendar.
    var warnsBeforeMeetings: Bool {
        didSet { defaults.set(warnsBeforeMeetings, forKey: Key.warnsBeforeMeetings) }
    }

    /// How many minutes before a meeting to warn, one of ``MeetingCheck/leadChoices``.
    var meetingWarningLead: Int {
        didSet { defaults.set(meetingWarningLead, forKey: Key.meetingWarningLead) }
    }

    /// Send a notification when the Mac uses clearly more power than usual for the time of day.
    var notifiesAboutUnusualDrain: Bool {
        didSet { defaults.set(notifiesAboutUnusualDrain, forKey: Key.notifiesAboutUnusualDrain) }
    }

    /// Send a notification when a new app is among the hungriest.
    var notifiesAboutNewApps: Bool {
        didSet { defaults.set(notifiesAboutNewApps, forKey: Key.notifiesAboutNewApps) }
    }

    /// The panel lists connected accessories with a battery.
    var showsAccessories: Bool {
        didSet { defaults.set(showsAccessories, forKey: Key.showsAccessories) }
    }

    /// A card slides in when AirPods or other headphones connect.
    var showsAccessoryCard: Bool {
        didSet { defaults.set(showsAccessoryCard, forKey: Key.showsAccessoryCard) }
    }

    var accessoryCardPosition: AccessoryCardPosition {
        didSet { defaults.set(accessoryCardPosition.rawValue, forKey: Key.accessoryCardPosition) }
    }

    /// Seconds the card stays, unless the pointer is over it.
    var accessoryCardDuration: Int {
        didSet { defaults.set(accessoryCardDuration, forKey: Key.accessoryCardDuration) }
    }

    /// Send a notification when an accessory's battery runs low.
    var notifiesWhenAccessoryLow: Bool {
        didSet { defaults.set(notifiesWhenAccessoryLow, forKey: Key.notifiesWhenAccessoryLow) }
    }

    /// The percentage an accessory notification is sent at.
    var accessoryLowBatteryLevel: Int {
        didSet { defaults.set(accessoryLowBatteryLevel, forKey: Key.accessoryLowBatteryLevel) }
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
    /// Levels an accessory notification can be sent at.
    static let accessoryLowBatteryChoices = [10, 15, 20, 25, 30]
    /// How long the AirPods card can stay, in seconds.
    static let accessoryCardDurations = [3, 5, 8, 12]

    @ObservationIgnored private let defaults: UserDefaults

    /// The settings the app runs with: the user's, or fresh ones of its own in an isolated run (see ``LaunchOptions``).
    static func forLaunch() -> AppSettings {
        guard LaunchOptions.isIsolated, let defaults = UserDefaults(suiteName: LaunchOptions.isolatedDefaultsDomain) else {
            return AppSettings()
        }
        defaults.removePersistentDomain(forName: LaunchOptions.isolatedDefaultsDomain)
        let settings = AppSettings(defaults: defaults)
        // The welcome panel would open on every isolated run; `--show-panel` opens it when it's wanted.
        settings.hasSeenWelcome = true
        return settings
    }

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
            Key.historyRange: HistoryRange.day.rawValue,
            Key.showsInsights: true,
            Key.warnsBeforeMeetings: false,
            Key.meetingWarningLead: MeetingCheck.defaultLead,
            Key.notifiesAboutUnusualDrain: false,
            Key.notifiesAboutNewApps: false,
            Key.showsAccessories: true,
            Key.showsAccessoryCard: true,
            Key.accessoryCardPosition: AccessoryCardPosition.belowIcon.rawValue,
            Key.accessoryCardDuration: 5,
            Key.notifiesWhenAccessoryLow: false,
            Key.accessoryLowBatteryLevel: 20,
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
        historyRange = HistoryRange(rawValue: defaults.string(forKey: Key.historyRange) ?? "") ?? .day
        showsInsights = defaults.bool(forKey: Key.showsInsights)
        warnsBeforeMeetings = defaults.bool(forKey: Key.warnsBeforeMeetings)
        let lead = defaults.integer(forKey: Key.meetingWarningLead)
        meetingWarningLead = MeetingCheck.leadChoices.contains(lead) ? lead : MeetingCheck.defaultLead
        notifiesAboutUnusualDrain = defaults.bool(forKey: Key.notifiesAboutUnusualDrain)
        notifiesAboutNewApps = defaults.bool(forKey: Key.notifiesAboutNewApps)
        showsAccessories = defaults.bool(forKey: Key.showsAccessories)
        showsAccessoryCard = defaults.bool(forKey: Key.showsAccessoryCard)
        accessoryCardPosition = AccessoryCardPosition(rawValue: defaults.string(forKey: Key.accessoryCardPosition) ?? "") ?? .belowIcon
        let duration = defaults.integer(forKey: Key.accessoryCardDuration)
        accessoryCardDuration = Self.accessoryCardDurations.contains(duration) ? duration : 5
        notifiesWhenAccessoryLow = defaults.bool(forKey: Key.notifiesWhenAccessoryLow)
        let accessoryLevel = defaults.integer(forKey: Key.accessoryLowBatteryLevel)
        accessoryLowBatteryLevel = Self.accessoryLowBatteryChoices.contains(accessoryLevel) ? accessoryLevel : 20
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
        static let historyRange = "historyRange"
        static let showsInsights = "showsInsights"
        static let warnsBeforeMeetings = "warnsBeforeMeetings"
        static let meetingWarningLead = "meetingWarningLead"
        static let notifiesAboutUnusualDrain = "notifiesAboutUnusualDrain"
        static let notifiesAboutNewApps = "notifiesAboutNewApps"
        static let showsAccessories = "showsAccessories"
        static let showsAccessoryCard = "showsAccessoryCard"
        static let accessoryCardPosition = "accessoryCardPosition"
        static let accessoryCardDuration = "accessoryCardDuration"
        static let notifiesWhenAccessoryLow = "notifiesWhenAccessoryLow"
        static let accessoryLowBatteryLevel = "accessoryLowBatteryLevel"
        static let showsReplaceTip = "showsReplaceTip"
        static let hasSeenWelcome = "hasSeenWelcome"
        static let panelShortcut = "panelShortcut"
    }
}
