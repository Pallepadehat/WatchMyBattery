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
    let history: HistoryRecorder
    let insights = InsightsMonitor()
    let accessories = AccessoryMonitor()
    let chargeLimit = ChargeLimit()
    let sleep = SleepMonitor()

    init(settings: AppSettings = AppSettings(), history: HistoryRecorder? = nil) {
        self.settings = settings
        // Opened with the chosen retention, as opening it already lets go of anything older.
        self.history = history ?? HistoryRecorder(retention: settings.historyRetention.interval)
    }

    /// Opens the panel under the menu bar icon (set up by the app delegate).
    @ObservationIgnored var showPanel: () -> Void = {}
    /// Opens the panel, or closes it if it's open: what the keyboard shortcut does.
    @ObservationIgnored var togglePanel: () -> Void = {}
    /// Slides in the AirPods card for these headphones (set up by the app delegate).
    @ObservationIgnored var showAccessoryCard: (Accessory) -> Void = { _ in }

    /// macOS wouldn't take the panel's keyboard shortcut, most likely because another app has it.
    private(set) var isPanelShortcutTaken = false

    /// The pane Settings shows.
    var settingsPane: SettingsPane? = .general

    /// The panel is on screen, so its animations may run.
    private(set) var isPanelOpen = false

    /// macOS's own battery is in the menu bar too; `nil` when we can't tell. Read each time the panel opens.
    private(set) var isBuiltInBatteryShown: Bool?

    /// "Two batteries in your menu bar?": only while there are two, and until it's dismissed.
    var showsReplaceTip: Bool {
        settings.showsReplaceTip && isBuiltInBatteryShown != false
    }

    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(model: self)

    func start() {
        battery.start()
        updater.start()
        notifier.start(model: self)
        history.start(model: self)
        insights.start(model: self)
        accessories.onArrival = { [weak self] accessory in
            guard let self, self.settings.showsAccessoryCard else { return }
            self.showAccessoryCard(accessory)
        }
        accessories.includesDevices = settings.showsDevices
        accessories.start()
        chargeLimit.start(model: self)
        sleep.start(model: self)
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
        // An isolated run would take the real app's shortcut away from it.
        guard !LaunchOptions.isIsolated else { return }
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
        insights.refresh()
        let shown = Self.readBuiltInBatteryShown()
        if shown != isBuiltInBatteryShown { isBuiltInBatteryShown = shown }
        accessories.includesDevices = settings.showsDevices
        accessories.refresh()
        chargeLimit.refresh()
        sleep.panelDidOpen()
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
        sleep.panelDidClose()
    }

    /// Keeps the hourly history this long from now on.
    func setHistoryRetention(_ retention: HistoryRetention) {
        settings.historyRetention = retention
        history.setRetention(retention.interval)
    }

    /// Shows or hides iPhones and iPads with the accessories.
    func setShowsDevices(_ shows: Bool) {
        settings.showsDevices = shows
        accessories.includesDevices = shows
    }

    /// The app is quitting: save what's left to save.
    func stop() {
        history.flush()
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

    /// Control Center's own setting for its battery (see ``ControlCenterBattery``). Reading it is one preferences
    /// lookup, done when the panel opens rather than watched, as nothing needs it in between.
    private static func readBuiltInBatteryShown() -> Bool? {
        let domain = ControlCenterBattery.domain as CFString
        // Control Center changes it from its own process, so drop what's cached first.
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        let value = CFPreferencesCopyValue(ControlCenterBattery.key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return ControlCenterBattery.isShownInMenuBar(flags: value as? Int)
    }

    /// The numbers behind the panel's estimates, for the current moment.
    var estimates: Estimates {
        Estimates(snapshot: battery.snapshot, systemWatts: usage.systemWatts)
    }
}
