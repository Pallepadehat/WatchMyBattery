import AppIntents
import BatteryKit
import Foundation

// Actions for Shortcuts and Spotlight. Each reads the battery straight from
// macOS when it runs, so it gives the same answer as the menu bar, whether or
// not the panel has been opened.

/// The battery's charge, as a percentage.
struct GetBatteryLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Level"
    static let description = IntentDescription(
        "Gets the battery's charge, as a percentage from 0 to 100.", categoryName: "Battery")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let snapshot = PowerSourceReader.read()
        guard snapshot.hasBattery else { throw BatteryIntentError.noBattery }
        let level = snapshot.level.formatted(.percent.precision(.fractionLength(0)))
        let dialog: IntentDialog =
            snapshot.isCharging
            ? "The battery is at \(level) and charging."
            : "The battery is at \(level)."
        return .result(value: snapshot.percentage, dialog: dialog)
    }
}

/// Time until the battery runs out, or until it's full while charging.
struct GetTimeLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Time Left"
    static let description = IntentDescription(
        "Gets how long the battery will last, or how long until it's full while charging. Empty while macOS is still calculating, or when the Mac is plugged in and not charging.",
        categoryName: "Battery")

    func perform() async throws -> some IntentResult & ReturnsValue<Measurement<UnitDuration>?> & ProvidesDialog {
        let snapshot = PowerSourceReader.read()
        guard snapshot.hasBattery else { throw BatteryIntentError.noBattery }
        let duration = snapshot.timeRemaining.map { Measurement(value: $0 / 60, unit: UnitDuration.minutes) }
        let dialog: IntentDialog
        switch (snapshot.chargeState, snapshot.timeRemaining) {
        case (.discharging, let time?): dialog = "About \(TimeFormat.clock(time)) left."
        case (.charging, let time?): dialog = "About \(TimeFormat.clock(time)) until full."
        case (.discharging, nil), (.charging, nil): dialog = "macOS is still calculating the time left."
        case (.charged, _): dialog = "The battery is fully charged."
        case (.notCharging, _): dialog = "The Mac is plugged in, and the battery isn't charging."
        }
        return .result(value: duration, dialog: dialog)
    }
}

/// The app using the most energy right now, measured for a couple of seconds.
struct GetHungriestAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Get App Using the Most Energy"
    static let description = IntentDescription(
        "Measures for a couple of seconds, then gets the name of the app using the most energy. Apps hidden in WatchMyBattery's settings are left out.",
        categoryName: "Battery")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> & ProvidesDialog {
        let monitor = AppUsageMonitor()
        monitor.excludedApps = Set(AppSettings().excludedApps)
        guard let app = await monitor.hungriestApp() else {
            return .result(value: nil, dialog: "No app is using much energy right now.")
        }
        let estimates = Estimates(snapshot: PowerSourceReader.read(), systemWatts: SystemPowerReader().currentWatts())
        let gained = estimates.timeGained(byQuitting: app.watts)
        let dialog: IntentDialog =
            gained >= 60
            ? "\(app.name) is using the most energy. Quitting it would give you about \(TimeFormat.compact(gained)) more."
            : "\(app.name) is using the most energy."
        return .result(value: app.name, dialog: dialog)
    }
}

enum BatteryIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noBattery

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noBattery: "This Mac doesn't have a battery."
        }
    }
}

/// Puts the actions in Spotlight and Shortcuts without any setup, with phrases for Siri.
struct WatchMyBatteryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetBatteryLevelIntent(),
            phrases: [
                "Get the battery level in \(.applicationName)",
                "How much battery is left in \(.applicationName)",
            ],
            shortTitle: "Battery Level",
            systemImageName: "battery.75percent")
        AppShortcut(
            intent: GetTimeLeftIntent(),
            phrases: [
                "Get the battery time left in \(.applicationName)",
                "How long will my battery last in \(.applicationName)",
            ],
            shortTitle: "Time Left",
            systemImageName: "clock")
        AppShortcut(
            intent: GetHungriestAppIntent(),
            phrases: [
                "Which app is using the most energy in \(.applicationName)",
                "Get the hungriest app in \(.applicationName)",
            ],
            shortTitle: "Hungriest App",
            systemImageName: "bolt.fill")
    }
}
