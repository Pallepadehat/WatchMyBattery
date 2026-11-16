import AppKit
import BatteryKit
import SwiftUI

/// Every notification WatchMyBattery can send, each with its switch.
struct NotificationsPane: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                LowBatteryRows(model: model)
            }
            Section {
                RunawayAppRows(model: model)
            }
            Section {
                MeetingWarningRows(model: model)
                InsightRows(model: model)
            } header: {
                Text("Insights")
            } footer: {
                Text("Insights also show in the panel. They're worked out on this Mac, from what WatchMyBattery already measures.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                ChargedNotificationRows(model: model)
                SleepDrainNotificationRows(model: model)
            } header: {
                Text("Charging and Sleep")
            }
            Section {
                AccessoryLowBatteryRows(model: model)
            }
        }
    }
}

// MARK: - Low battery

/// The low battery notification: on or off, and at which levels.
private struct LowBatteryRows: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.notifiesWhenLow) {
            SettingLabel("Low Battery", symbol: SettingIcon.lowBattery, color: .red) {
                Text("A notification naming the app using the most energy, with a button to quit it.")
            }
        }
        .requestsNotifications(whenOn: settings.notifiesWhenLow, from: model.notifier)
        .task { await model.notifier.refreshAuthorization() }

        if settings.notifiesWhenLow {
            LabeledContent("Notify At") {
                HStack(spacing: 4) {
                    ForEach(AppSettings.lowBatteryChoices.reversed(), id: \.self) { level in
                        LevelChip(level: level, isOn: settings.lowBatteryLevels.contains(level)) {
                            toggle(level)
                        }
                    }
                }
            }
            .padding(.leading, 34)

            NotificationsDeniedRow(notifier: model.notifier)
        }
    }

    private func toggle(_ level: Int) {
        var levels = Set(model.settings.lowBatteryLevels)
        if levels.contains(level) {
            // Keep at least one, or the switch above would be on for nothing.
            guard levels.count > 1 else { return }
            levels.remove(level)
        } else {
            levels.insert(level)
        }
        model.settings.lowBatteryLevels = levels.sorted(by: >)
    }
}

// MARK: - Accessories

/// The accessory low battery notification: on or off, and at which level.
private struct AccessoryLowBatteryRows: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.notifiesWhenAccessoryLow) {
            SettingLabel("Accessories Running Low", symbol: "airpodspro", color: .cyan) {
                Text("A notification when AirPods, a Magic Mouse or another accessory needs charging.")
            }
        }
        .requestsNotifications(whenOn: settings.notifiesWhenAccessoryLow, from: model.notifier)

        if settings.notifiesWhenAccessoryLow {
            LabeledContent("Notify At") {
                HStack(spacing: 4) {
                    ForEach(AppSettings.accessoryLowBatteryChoices.reversed(), id: \.self) { level in
                        LevelChip(level: level, isOn: settings.accessoryLowBatteryLevel == level) {
                            settings.accessoryLowBatteryLevel = level
                        }
                    }
                }
            }
            .padding(.leading, 34)

            NotificationsDeniedRow(notifier: model.notifier)
        }
    }
}

// MARK: - Apps using a lot

/// The runaway app notification, which needs the history's measurements.
private struct RunawayAppRows: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.notifiesAboutRunawayApps) {
            SettingLabel("Apps Using a Lot of Energy", symbol: "flame.fill", color: .orange) {
                Text("A notification when an app keeps using a lot of power on battery for a while, with a button to quit it. Not for the app you're using.")
            }
        }
        .disabled(!settings.recordsHistory)
        .requestsNotifications(whenOn: settings.notifiesAboutRunawayApps, from: model.notifier)

        if !settings.recordsHistory {
            NeedsHistoryNote()
        } else if settings.notifiesAboutRunawayApps {
            NotificationsDeniedRow(notifier: model.notifier)
        }
    }
}

// MARK: - Insights

/// "Charge before your meeting": on or off, how far ahead, and calendar access.
///
/// Turning it on doesn't bring up macOS's prompt by itself: the Calendar Access row below it says why access is
/// needed, and asks only when you click "Allow Access…".
private struct MeetingWarningRows: View {
    let model: AppModel

    private var calendar: CalendarWatcher { model.insights.calendar }

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.warnsBeforeMeetings) {
            SettingLabel("Charge Before Meetings", symbol: "calendar.badge.clock", color: .red) {
                Text("When the battery won't last through your next meeting. Uses the Calendar app, and only reads when events start and end.")
            }
        }
        .requestsNotifications(whenOn: settings.warnsBeforeMeetings, from: model.notifier)
        .onAppear { calendar.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings, where access may have been turned on or off.
            calendar.refreshAccess()
            Task { await model.notifier.refreshAuthorization() }
        }

        if settings.warnsBeforeMeetings {
            CalendarAccessRow(calendar: calendar)

            // How far ahead only matters once there's a calendar to read.
            if calendar.access == .granted {
                Picker(selection: $settings.meetingWarningLead) {
                    ForEach(MeetingCheck.leadChoices, id: \.self) { minutes in
                        Text(Self.leadTitle(minutes)).tag(minutes)
                    }
                } label: {
                    Text("Warn")
                }
                .padding(.leading, 34)
            }

            if calendar.access == .granted, model.notifier.isDenied {
                LabeledContent {
                    Button("Open…") { model.notifier.openNotificationSettings() }
                } label: {
                    Label("Notifications are turned off, so it only shows in the panel.", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(InlineIconLabelStyle(color: .orange))
                        .font(.caption)
                }
                .padding(.leading, 34)
            }
        }
    }

    /// "30 minutes before", "1 hour before", "1 hour, 30 minutes before".
    private static func leadTitle(_ minutes: Int) -> String {
        let duration = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return String(localized: "\(duration) before")
    }
}

/// Whether WatchMyBattery may read the calendar, laid out like the Low Power Mode helper's row, and the one place
/// that asks: "Allow…" brings up macOS's prompt; once that's been answered no, "Open…" goes to System Settings, since
/// macOS won't ask twice.
private struct CalendarAccessRow: View {
    let calendar: CalendarWatcher

    var body: some View {
        LabeledContent {
            switch calendar.access {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(InlineIconLabelStyle(color: .green))
            case .notDetermined:
                Button("Allow…") { Task { await calendar.requestAccess() } }
                    .disabled(calendar.isRequestingAccess)
            case .denied:
                Button("Open…") { calendar.openPrivacySettings() }
            }
        } label: {
            SettingLabel("Calendar Access", symbol: "calendar", color: .red) {
                if calendar.access == .denied {
                    Text("Turned off in System Settings › Privacy & Security › Calendars.")
                } else {
                    Text("Reads only when your meetings start and end. macOS asks you to allow it once.")
                }
            }
        }
    }
}

/// "More than usual" and "a new app", which need the history's two weeks.
private struct InsightRows: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.notifiesAboutUnusualDrain) {
            SettingLabel("More Than Usual", symbol: "chart.line.uptrend.xyaxis", color: .purple) {
                Text(
                    "When the Mac uses clearly more power than it usually does at this time of day, and which app is behind it. Once it knows what's usual, after about a week."
                )
            }
        }
        .disabled(!settings.recordsHistory)
        .requestsNotifications(whenOn: settings.notifiesAboutUnusualDrain, from: model.notifier)

        Toggle(isOn: $settings.notifiesAboutNewApps) {
            SettingLabel("New Apps Using a Lot", symbol: "sparkles", color: .blue) {
                Text("When an app that hadn't used much battery in the last two weeks is now among the hungriest.")
            }
        }
        .disabled(!settings.recordsHistory)
        .requestsNotifications(whenOn: settings.notifiesAboutNewApps, from: model.notifier)

        if !settings.recordsHistory {
            NeedsHistoryNote()
        } else if settings.notifiesAboutUnusualDrain || settings.notifiesAboutNewApps {
            NotificationsDeniedRow(notifier: model.notifier)
        }
    }
}
