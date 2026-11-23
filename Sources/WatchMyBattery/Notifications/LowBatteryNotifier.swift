import AppKit
import BatteryKit
import OSLog
import Observation
import UserNotifications

/// Sends a notification when the battery runs low, naming the app that's
/// using the most energy, with a button that quits it. It also sends the
/// runaway app notification for ``HistoryRecorder``, the insights for
/// ``InsightsMonitor``, the sleep notification for ``SleepMonitor``, and the
/// charged and accessory low battery notifications, as they share the Quit
/// and Low Power Mode buttons and macOS allows one notification delegate.
///
/// It only watches the battery snapshot, which changes by notification, so
/// it costs nothing until a level is reached. Then it measures apps for a
/// couple of seconds to find the hungriest one.
@Observable
final class LowBatteryNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// macOS won't show our notifications: the user turned them off in System Settings.
    private(set) var isDenied = false

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var alert = LowBatteryAlert()
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var wasEnabled = false
    @ObservationIgnored private var accessoryAlert = AccessoryLowBatteryAlert(notified: LowBatteryNotifier.savedAccessoriesNotified)
    @ObservationIgnored private var chargedAlert = ChargeLevelAlert()
    /// Every kind of notification's buttons; macOS takes them all at once.
    @ObservationIgnored private var categories: [String: UNNotificationCategory] = [:]

    private static let categoryID = "lowBattery"
    private static let meetingCategoryID = "meeting"
    private static let meetingID = "meeting"
    private static let quitActionID = "quit"
    private static let lowPowerModeActionID = "lowPowerMode"
    /// What clicking a notification opens, when it's not the panel.
    nonisolated private static let opensKey = "opens"
    nonisolated private static let opensHistory = "history"

    func start(model: AppModel) {
        self.model = model
        center.delegate = self
        wasEnabled = model.settings.notifiesWhenLow
        Task { await refreshAuthorization() }
        observe()
        observeAccessories()
        observeCharging()
    }

    /// Asks for permission the first time notifications are turned on.
    func requestAuthorization() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        isDenied = !granted
        if !granted { Logger.app.notice("Notifications weren't allowed") }
    }

    func refreshAuthorization() async {
        let status = await center.notificationSettings().authorizationStatus
        isDenied = status == .denied
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Watching the battery

    private func observe() {
        guard let model else { return }
        let (level, enabled) = withObservationTracking {
            let enabled = model.settings.notifiesWhenLow
            return (alert.update(with: model.battery.snapshot, levels: enabled ? model.settings.lowBatteryLevels : []), enabled)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        // Turning notifications on (or adding a level) while already below it doesn't notify right away.
        let justEnabled = enabled && !wasEnabled
        wasEnabled = enabled
        if let level, !justEnabled { Task { await notify(level: level) } }
    }

    private func notify(level: Int) async {
        guard let model else { return }
        let snapshot = model.battery.snapshot
        let app = await model.usage.hungriestApp()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Battery at \(snapshot.level.formatted(.percent.precision(.fractionLength(0))))")
        let timeLeft = snapshot.timeRemaining.map { String(localized: "About \(TimeFormat.clock($0)) left.") }
        var actions: [UNNotificationAction] = []
        if let app {
            let cost = Estimates(snapshot: snapshot, systemWatts: model.usage.systemWatts).timeGained(byQuitting: app.watts)
            let hint =
                cost >= 60
                ? String(localized: "\(app.name) is using the most energy. Quitting it would give you about \(TimeFormat.compact(cost)) more.")
                : String(localized: "\(app.name) is using the most energy.")
            content.body = [timeLeft, hint].compactMap(\.self).joined(separator: " ")
            content.userInfo = ["pid": Int(app.id), "bundleIdentifier": app.bundleIdentifier ?? ""]
            actions.append(
                UNNotificationAction(identifier: Self.quitActionID, title: String(localized: "Quit \(app.name)"), options: [.destructive]))
        } else {
            content.body = timeLeft ?? String(localized: "Plug in soon.")
        }
        if model.lowPowerMode.isSupported, !snapshot.isLowPowerModeOn {
            actions.append(
                UNNotificationAction(identifier: Self.lowPowerModeActionID, title: String(localized: "Turn On Low Power Mode")))
        }
        if !actions.isEmpty {
            register(UNNotificationCategory(identifier: Self.categoryID, actions: actions, intentIdentifiers: []))
            content.categoryIdentifier = Self.categoryID
        }
        content.sound = .default
        // One notification at a time: a lower level replaces the one before.
        await send(UNNotificationRequest(identifier: "lowBattery", content: content, trigger: nil), kind: "low battery")
    }

    // MARK: - Charged

    /// Followed even while off, so turning it on mid-charge, already past the level, doesn't notify right away.
    private func observeCharging() {
        guard let model else { return }
        let wasSpent = chargedAlert.isSpent
        let (reached, enabled, level) = withObservationTracking {
            // A charge limit below the level stops the battery first: it's charged as far as it goes at the limit.
            let level = min(model.settings.chargedLevel, model.battery.chargeLimit ?? 100)
            return (chargedAlert.update(with: model.battery.snapshot, target: level), model.settings.notifiesWhenCharged, level)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeCharging() }
        }
        // Unplugged after it went out: it's done its job.
        if wasSpent, !chargedAlert.isSpent, !model.battery.snapshot.isPluggedIn { removeChargedNotification() }
        guard reached, enabled else { return }
        Task { await notifyCharged(level: level) }
    }

    /// "Charged to 80%: unplug now to keep the battery healthy", or "Fully charged".
    private func notifyCharged(level: Int) async {
        let content = UNMutableNotificationContent()
        let percent = (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
        if level >= 100 {
            content.title = String(localized: "Fully charged")
            content.body = String(localized: "You can unplug your Mac.")
        } else {
            content.title = String(localized: "Charged to \(percent)")
            content.body = String(localized: "Unplug now to keep the battery between 20% and \(percent), where it wears the least.")
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        await send(UNNotificationRequest(identifier: "charged", content: content, trigger: nil), kind: "charged")
    }

    /// Unplugged: the "charged" notification has done its job.
    func removeChargedNotification() {
        center.removeDeliveredNotifications(withIdentifiers: ["charged"])
    }

    // MARK: - Sleep

    /// "Your Mac used 18% while asleep": much more than a sleep should, with what usually causes it.
    func notifySleepDrain(_ session: SleepSession, typical: Double?) async {
        guard let used = session.used else { return }
        let content = UNMutableNotificationContent()
        let percent = (Double(used) / 100).formatted(.percent.precision(.fractionLength(0)))
        content.title = String(localized: "Your Mac used \(percent) while asleep")
        let hours = DurationText.spoken(session.duration)
        if let typical, let rate = session.perHour, rate > typical * 2 {
            let ratio = Int((rate / max(typical, 0.1)).rounded())
            content.body = String(
                localized: "In \(hours), about \(ratio) times faster than usual. Something may be waking it: open the panel to see what's keeping it awake.")
        } else {
            content.body = String(localized: "In \(hours). A Mac asleep should use about 1% an hour. Open the panel to see what's keeping it awake.")
        }
        content.sound = .default
        await send(UNNotificationRequest(identifier: "sleepDrain", content: content, trigger: nil), kind: "sleep drain")
    }

    // MARK: - Accessories

    private func observeAccessories() {
        guard let model else { return }
        let (low, enabled) = withObservationTracking {
            // Only what was just read: a phone's level kept from a while ago (from before a relaunch, say) may be long
            // out of date, and it's been plugged in since.
            let current = model.accessories.accessories.filter { model.accessories.staleReadDate(of: $0) == nil }
            // Followed even while off, so turning it on with an accessory already low doesn't notify right away.
            return (
                accessoryAlert.update(with: current, threshold: model.settings.accessoryLowBatteryLevel),
                model.settings.notifiesWhenAccessoryLow
            )
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAccessories() }
        }
        Self.saveAccessoriesNotified(accessoryAlert.notified)
        guard enabled else { return }
        for accessory in low { Task { await notify(accessory) } }
    }

    private static let accessoriesNotifiedKey = "accessoriesNotifiedLow"

    /// The accessories already notified about, kept across launches so a relaunch doesn't tell you again.
    private static var savedAccessoriesNotified: Set<String> {
        guard !LaunchOptions.isIsolated else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: accessoriesNotifiedKey) ?? [])
    }

    private static func saveAccessoriesNotified(_ notified: Set<String>) {
        guard !LaunchOptions.isIsolated, notified != savedAccessoriesNotified else { return }
        UserDefaults.standard.set(notified.sorted(), forKey: accessoriesNotifiedKey)
    }

    /// "AirPods Pro at 15%": the lowest earbud, or the only battery.
    private func notify(_ accessory: Accessory) async {
        guard let level = accessory.lowestLevel else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(accessory.name) at \((Double(level) / 100).formatted(.percent.precision(.fractionLength(0))))")
        switch accessory.kind {
        case .earbuds:
            let earbuds = accessory.parts.filter(\.role.isEarbud).map(\.spokenDescription).joined(separator: ", ")
            content.body = String(localized: "\(earbuds). Put them in their case to charge.")
        case .keyboard, .mouse, .trackpad:
            content.body = String(localized: "Connect its cable to charge it.")
        case .phone, .tablet, .watch:
            content.body = String(localized: "Plug it in soon.")
        case .headphones, .gameController, .other:
            content.body = String(localized: "Charge it soon.")
        }
        content.sound = .default
        // One per accessory: if it's reported again later, the new one replaces the old.
        await send(UNNotificationRequest(identifier: "accessory-\(accessory.id)", content: content, trigger: nil), kind: "accessory")
    }

    // MARK: - Rules

    /// "Battery at 20%: Turned on Low Power Mode. Quit Docker." A rule ran, and this is what it did.
    func notifyRuleRan(_ rule: BatteryRule, did done: [String]) async {
        let content = UNMutableNotificationContent()
        content.title = RuleText.notificationTitle(for: rule.trigger)
        content.body = done.isEmpty ? String(localized: "Your rule ran.") : done.joined(separator: " ")
        content.sound = .default
        // One per rule: the next time it runs replaces this one.
        await send(UNNotificationRequest(identifier: "rule-\(rule.id.uuidString)", content: content, trigger: nil), kind: "rule")
    }

    // MARK: - Weekly summary

    /// "Last week: 14 hours on battery": the week before, at a glance. Clicking it opens Settings › History.
    func notifyWeeklySummary(_ summary: WeeklySummary) async {
        let content = UNMutableNotificationContent()
        content.title = WeeklySummaryText.notificationTitle(summary)
        content.body = WeeklySummaryText.notificationBody(summary)
        content.userInfo = [Self.opensKey: Self.opensHistory]
        content.sound = .default
        await send(UNNotificationRequest(identifier: "weeklySummary", content: content, trigger: nil), kind: "weekly summary")
    }

    // MARK: - Runaway apps

    /// "Figma is using a lot of energy": an app has kept up a high power draw for `minutes`, on battery.
    func notifyRunaway(_ app: BatteryHistory.AppIdentity, pid: pid_t, minutes: Int, timeGained: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(app.name) is using a lot of energy")
        content.body =
            timeGained >= 60
            ? String(localized: "For \(minutes) minutes now. Quitting it would give you about \(TimeFormat.compact(timeGained)) more.")
            : String(localized: "For \(minutes) minutes now.")
        addQuitButton(for: app, pid: pid, to: content)
        content.sound = .default
        // One per app: if it's reported again later, the new one replaces the old.
        await send(UNNotificationRequest(identifier: "runaway-\(app.key)", content: content, trigger: nil), kind: "runaway app")
    }

    // MARK: - Insights

    /// "Charge before your 14:00 meeting". One at a time: a later warning replaces the one before.
    func notifyMeeting(_ warning: MeetingWarning, offersLowPowerMode: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = InsightText.meetingTitle(warning)
        content.body = InsightText.meetingDetail(warning)
        if offersLowPowerMode {
            register(
                UNNotificationCategory(
                    identifier: Self.meetingCategoryID,
                    actions: [UNNotificationAction(identifier: Self.lowPowerModeActionID, title: String(localized: "Turn On Low Power Mode"))],
                    intentIdentifiers: []))
            content.categoryIdentifier = Self.meetingCategoryID
        }
        content.sound = .default
        await send(UNNotificationRequest(identifier: Self.meetingID, content: content, trigger: nil), kind: "meeting")
    }

    /// Plugged in: the meeting warning has done its job, so it leaves Notification Center.
    func removeMeetingNotification() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.meetingID])
    }

    /// "Using more power than usual", with a button that quits the app behind it while it's running.
    func notifyUnusualDrain(_ drain: UnusualDrain, cause running: NSRunningApplication?) async {
        let content = UNMutableNotificationContent()
        content.title = InsightText.unusualDrainTitle
        content.body = InsightText.unusualDrainDetail(drain)
        if let cause = drain.cause, let running { addQuitButton(for: cause, pid: running.processIdentifier, to: content) }
        content.sound = .default
        await send(UNNotificationRequest(identifier: "unusualDrain", content: content, trigger: nil), kind: "more than usual")
    }

    /// "Figma is new, and using a lot of battery". Sent once per app.
    func notifyNewApp(_ app: BatteryHistory.AppIdentity, running: NSRunningApplication?) async {
        let content = UNMutableNotificationContent()
        content.title = InsightText.newAppTitle(app)
        content.body = InsightText.newAppDetail
        if let running { addQuitButton(for: app, pid: running.processIdentifier, to: content) }
        content.sound = .default
        await send(UNNotificationRequest(identifier: "newApp-\(app.key)", content: content, trigger: nil), kind: "new app")
    }

    /// A "Quit Figma" button. Each app gets a category of its own: if they shared one, a later notification for another
    /// app would put that app's name on the button of one still in Notification Center.
    private func addQuitButton(for app: BatteryHistory.AppIdentity, pid: pid_t, to content: UNMutableNotificationContent) {
        content.userInfo = ["pid": Int(pid), "bundleIdentifier": app.bundleIdentifier ?? ""]
        let category = "quit-\(app.key)"
        register(
            UNNotificationCategory(
                identifier: category,
                actions: [UNNotificationAction(identifier: Self.quitActionID, title: String(localized: "Quit \(app.name)"), options: [.destructive])],
                intentIdentifiers: []))
        content.categoryIdentifier = category
    }

    private func send(_ request: UNNotificationRequest, kind: String) async {
        do {
            try await center.add(request)
        } catch {
            Logger.app.error("Couldn't send the \(kind, privacy: .public) notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func register(_ category: UNNotificationCategory) {
        guard categories[category.identifier] != category else { return }
        categories[category.identifier] = category
        center.setNotificationCategories(Set(categories.values))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let pid = (info["pid"] as? Int).map { pid_t($0) }
        let bundleIdentifier = info["bundleIdentifier"] as? String
        let action = response.actionIdentifier
        let opens = info[Self.opensKey] as? String
        await MainActor.run {
            if action == Self.quitActionID, let pid {
                // Check it's still the same app: process IDs get reused.
                guard let app = NSRunningApplication(processIdentifier: pid),
                    bundleIdentifier?.isEmpty != false || app.bundleIdentifier == bundleIdentifier
                else { return }
                app.terminate()
            } else if action == Self.lowPowerModeActionID {
                model?.setLowPowerMode(true)
            } else if action == UNNotificationDefaultActionIdentifier, opens == Self.opensHistory {
                model?.openHistory()
            } else if action == UNNotificationDefaultActionIdentifier {
                model?.showPanel()
            }
        }
    }
}
