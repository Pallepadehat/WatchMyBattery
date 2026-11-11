import AppKit
import BatteryKit
import Observation

/// Owns the app's long-lived pieces and the actions that span them.
@Observable
final class AppModel {
    let settings: AppSettings
    let battery = BatteryMonitor()
    let usage = AppUsageMonitor()
    let updater = Updater()
    let launchAtLogin = LaunchAtLogin()
    let notifier = LowBatteryNotifier()

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    /// Opens the panel under the menu bar icon (set up by the app delegate).
    @ObservationIgnored var showPanel: () -> Void = {}

    /// The pane Settings shows.
    var settingsPane: SettingsPane? = .general

    /// The panel is on screen, so its animations may run.
    private(set) var isPanelOpen = false

    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(model: self)

    func start() {
        battery.start()
        updater.start()
        notifier.start(model: self)
        usage.excludedApps = Set(settings.excludedApps)
    }

    /// The panel is open: start measuring which apps use energy.
    func panelDidOpen() {
        isPanelOpen = true
        usage.maximumApps = settings.maximumApps
        usage.excludedApps = Set(settings.excludedApps)
        usage.start()
        battery.refreshHealthIfNeeded()
    }

    /// Never give this app a slice again (from its slice's menu, or Settings).
    func exclude(_ app: AppUsage) {
        guard let bundleIdentifier = app.bundleIdentifier else { return }
        settings.exclude(bundleIdentifier: bundleIdentifier)
        usage.excludedApps = Set(settings.excludedApps)
    }

    func removeExclusion(_ bundleIdentifier: String) {
        settings.excludedApps.removeAll { $0 == bundleIdentifier }
        usage.excludedApps = Set(settings.excludedApps)
    }

    func panelDidClose() {
        isPanelOpen = false
        usage.stop()
    }

    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        settingsWindow.show()
    }

    /// System Settings › Battery.
    func openBatterySettings() {
        SystemSettings.open(.battery)
    }

    /// System Settings › Control Center, where the built-in battery icon can be hidden.
    func openControlCenterSettings() {
        SystemSettings.open(.controlCenter)
    }

    /// The numbers behind the panel's estimates, for the current moment.
    var estimates: Estimates {
        Estimates(snapshot: battery.snapshot, systemWatts: usage.systemWatts)
    }
}
