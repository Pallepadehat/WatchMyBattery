import AppKit
import BatteryKit
import Foundation

/// How rules read, in Settings and their notifications.
enum RuleText {
    static func percent(_ level: Int) -> String {
        (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "When the battery drops to 20%".
    static func trigger(_ trigger: BatteryRule.Trigger) -> String {
        switch trigger {
        case .dropsTo(let level): String(localized: "When the battery drops to \(percent(level))")
        case .chargesTo(let level): String(localized: "When the battery charges to \(percent(level))")
        case .pluggedIn: String(localized: "When the charger is connected")
        case .unplugged: String(localized: "When the charger is disconnected")
        }
    }

    /// The kind of trigger, without its level, for the picker.
    static func triggerKind(_ trigger: BatteryRule.Trigger) -> String {
        switch trigger {
        case .dropsTo: String(localized: "Battery drops to")
        case .chargesTo: String(localized: "Battery charges to")
        case .pluggedIn: String(localized: "Charger connected")
        case .unplugged: String(localized: "Charger disconnected")
        }
    }

    static func triggerSymbol(_ trigger: BatteryRule.Trigger) -> String {
        switch trigger {
        case .dropsTo: "battery.25percent"
        case .chargesTo: "battery.100percent.bolt"
        case .pluggedIn: "powerplug.fill"
        case .unplugged: "powerplug.portrait"
        }
    }

    /// "Turn on Low Power Mode", "Quit Docker and Figma".
    static func action(_ action: BatteryRule.Action) -> String {
        switch action {
        case .lowPowerMode(true): String(localized: "Turn on Low Power Mode")
        case .lowPowerMode(false): String(localized: "Turn off Low Power Mode")
        case .quitApps(let apps) where apps.isEmpty: String(localized: "Quit apps")
        case .quitApps(let apps): String(localized: "Quit \(apps.map(appName).formatted(.list(type: .and)))")
        case .runShortcut(let name) where name.isEmpty: String(localized: "Run a shortcut")
        case .runShortcut(let name): String(localized: "Run “\(name)”")
        case .notify: String(localized: "Send a notification")
        case .chargeLimit(let level) where level >= 100: String(localized: "Turn off the charge limit")
        case .chargeLimit(let level): String(localized: "Limit charging to \(percent(level))")
        }
    }

    static func actionSymbol(_ action: BatteryRule.Action) -> String {
        switch action {
        case .lowPowerMode: "leaf.fill"
        case .quitApps: "xmark.app.fill"
        case .runShortcut: "square.2.layers.3d.top.filled"
        case .notify: "bell.badge.fill"
        case .chargeLimit: "battery.75percent"
        }
    }

    /// "Battery at 20%", "Charger connected": the notification a rule sends.
    static func notificationTitle(for trigger: BatteryRule.Trigger) -> String {
        switch trigger {
        case .dropsTo(let level), .chargesTo(let level): String(localized: "Battery at \(percent(level))")
        case .pluggedIn: String(localized: "Charger connected")
        case .unplugged: String(localized: "Charger disconnected")
        }
    }

    /// An app's name from its bundle identifier, as Finder shows it; the identifier when it isn't installed.
    static func appName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return bundleIdentifier }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// How the weekly summary reads, in its notification and Settings › History.
enum WeeklySummaryText {
    /// "Last week: 14 hours on battery".
    static func notificationTitle(_ summary: WeeklySummary) -> String {
        String(localized: "Last week: \(DurationText.spoken(summary.totals.batterySeconds)) on battery")
    }

    /// "1.5 charges' worth, 20% more than the week before. Figma used the most."
    static func notificationBody(_ summary: WeeklySummary) -> String {
        var sentences: [String] = [used(summary)]
        if let top = summary.topApps.first {
            sentences.append(String(localized: "\(top.app.name) used the most."))
        }
        if let grew = summary.biggestRise, grew.app != summary.topApps.first?.app {
            sentences.append(rise(grew))
        }
        return sentences.joined(separator: " ")
    }

    /// "1.5 charges' worth, 20% more than the week before."
    static func used(_ summary: WeeklySummary) -> String {
        let charges = summary.totals.charges.formatted(.number.precision(.fractionLength(0...1)))
        guard let change = summary.drainedChange, abs(change) >= 0.05 else {
            return String(localized: "\(charges) charges' worth of battery.")
        }
        let amount = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return change > 0
            ? String(localized: "\(charges) charges' worth of battery, \(amount) more than the week before.")
            : String(localized: "\(charges) charges' worth of battery, \(amount) less than the week before.")
    }

    /// "Figma used three times as much as the week before", or "Figma is new this week".
    static func rise(_ rise: WeeklySummary.Rise) -> String {
        guard rise.previousJoules > 0 else { return String(localized: "\(rise.app.name) is new, and used a fair share.") }
        if rise.ratio >= 1.95 {
            return String(localized: "\(rise.app.name) used \(Int(rise.ratio.rounded())) times as much as the week before.")
        }
        let more = (rise.ratio - 1).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(rise.app.name) used \(more) more than the week before.")
    }

    /// "+20%" or "−15%", for a change beside a number; `nil` when it's too small to mention.
    static func change(_ value: Double?) -> String? {
        guard let value, abs(value) >= 0.05 else { return nil }
        let amount = abs(value).formatted(.percent.precision(.fractionLength(0)))
        return value > 0 ? "+" + amount : "\u{2212}" + amount
    }
}
