import AppKit
import BatteryKit
import OSLog
import Observation
import UserNotifications

/// Sends a notification when the battery runs low, naming the app that's
/// using the most energy, with a button that quits it.
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

    private static let categoryID = "lowBattery"
    private static let quitActionID = "quit"
    private static let lowPowerModeActionID = "lowPowerMode"

    func start(model: AppModel) {
        self.model = model
        center.delegate = self
        wasEnabled = model.settings.notifiesWhenLow
        Task { await refreshAuthorization() }
        observe()
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
        content.title = String(localized: "Battery at \(snapshot.percentage)%")
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
            center.setNotificationCategories([
                UNNotificationCategory(identifier: Self.categoryID, actions: actions, intentIdentifiers: [])
            ])
            content.categoryIdentifier = Self.categoryID
        }
        content.sound = .default
        // One notification at a time: a lower level replaces the one before.
        let request = UNNotificationRequest(identifier: "lowBattery", content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Logger.app.error("Couldn't send the low battery notification: \(error.localizedDescription, privacy: .public)")
        }
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
        await MainActor.run {
            if action == Self.quitActionID, let pid {
                // Check it's still the same app: process IDs get reused.
                guard let app = NSRunningApplication(processIdentifier: pid),
                    bundleIdentifier?.isEmpty != false || app.bundleIdentifier == bundleIdentifier
                else { return }
                app.terminate()
            } else if action == Self.lowPowerModeActionID {
                model?.setLowPowerMode(true)
            } else if action == UNNotificationDefaultActionIdentifier {
                model?.showPanel()
            }
        }
    }
}
