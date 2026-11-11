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
    let lowPowerMode = LowPowerMode()

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    /// Opens the panel under the menu bar icon (set up by the app delegate).
    @ObservationIgnored var showPanel: () -> Void = {}
    /// Opens the panel, or closes it if it's open: what the keyboard shortcut does.
    @ObservationIgnored var togglePanel: () -> Void = {}

    /// macOS wouldn't take the panel's keyboard shortcut, most likely because another app has it.
    private(set) var isPanelShortcutTaken = false

    /// The pane Settings shows.
    var settingsPane: SettingsPane? = .general

    /// The panel is on screen, so its animations may run.
    private(set) var isPanelOpen = false

    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(model: self)

    func start() {
        battery.start()
        updater.start()
        notifier.start(model: self)
        lowPowerMode.checkSupport()
        usage.excludedApps = Set(settings.excludedApps)
        GlobalHotkey.shared.action = { [weak self] in self?.togglePanel() }
        registerPanelShortcut()
    }

    /// Saves the panel's keyboard shortcut and starts listening for it; `nil` removes it.
    func setPanelShortcut(_ hotkey: Hotkey?) {
        settings.panelShortcut = hotkey
        registerPanelShortcut()
    }

    /// Stops listening for the shortcut while a new one is being recorded, so pressing the old one records it rather than opening the panel.
    func pausePanelShortcut() {
        GlobalHotkey.shared.register(nil)
    }

    func registerPanelShortcut() {
        isPanelShortcutTaken = !GlobalHotkey.shared.register(settings.panelShortcut)
    }

    /// Turns Low Power Mode on or off; macOS asks for an administrator's password first.
    func setLowPowerMode(_ on: Bool) {
        lowPowerMode.set(on)
    }

    /// The panel is open: start measuring which apps use energy.
    func panelDidOpen() {
        isPanelOpen = true
        usage.maximumApps = settings.maximumApps
        usage.excludedApps = Set(settings.excludedApps)
        usage.start()
        battery.refreshHealthIfNeeded()
        // The suggestion to turn on Low Power Mode comes back after a charge.
        if battery.snapshot.isPluggedIn { lowPowerMode.isSuggestionDismissed = false }
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
