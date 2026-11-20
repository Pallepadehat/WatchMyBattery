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
    let powerDraw = PowerDrawMonitor()
    let chime = ChargingChime()
    let usageStats = UsageStats()

    init(settings: AppSettings = AppSettings(), history: HistoryRecorder? = nil) {
        self.settings = settings
        #if DEBUG
            // Every period of a made-up history, but never by changing the real app's settings.
            if LaunchOptions.pretendsHistory, LaunchOptions.isIsolated { settings.historyRetention = .year }
        #endif
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

    /// An app for Settings › History to open, set from the panel; the pane takes it once it's there.
    var historyApp: String?

    /// The panel is on screen, so its animations may run.
    private(set) var isPanelOpen = false

    /// The tallest the panel's card may be: the room between the menu bar and the bottom of the screen it opens on.
    /// Past that, its middle scrolls, with the header and the menu items staying put.
    var panelMaxHeight: CGFloat = .infinity

    /// macOS's own battery is in the menu bar too; `nil` when we can't tell. Read each time the panel opens.
    private(set) var isBuiltInBatteryShown: Bool?

    /// "Two batteries in your menu bar?": only while there are two, and until it's dismissed.
    var showsReplaceTip: Bool {
        settings.showsReplaceTip && isBuiltInBatteryShown != false
    }

    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(model: self)
    @ObservationIgnored private lazy var onboardingWindow = OnboardingWindowController(model: self)

    func start() {
        battery.start()
        updater.start()
        usageStats.start(settings: settings)
        notifier.start(model: self)
        chime.start(model: self)
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

    /// Turns Low Power Mode on or off, through the helper once it's allowed, or else after macOS asks for a password.
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
        refreshBuiltInBatteryShown()
        accessories.includesDevices = settings.showsDevices
        accessories.refresh()
        chargeLimit.refresh()
        sleep.startReadingHolders(for: .panel)
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
        sleep.stopReadingHolders(for: .panel)
    }

    /// Keeps the hourly history this long from now on.
    func setHistoryRetention(_ retention: HistoryRetention) {
        settings.historyRetention = retention
        // Settings › History can't look further back than what's kept.
        settings.historyPeriod = settings.historyPeriod.limited(to: retention)
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

    /// The welcome tour: on first launch, and from Settings › General.
    func openOnboarding(at step: OnboardingView.Step = .welcome) {
        onboardingWindow.show(at: step)
    }

    #if DEBUG
        /// Forgets the tour was seen, as on a first launch, and opens it from the start: for working on it. Debug
        /// builds only (the menu bar icon's menu, or `--reset-onboarding`).
        func resetOnboarding() {
            settings.hasCompletedOnboarding = false
            openOnboarding()
        }
    #endif

    /// Whether macOS's own battery is in the menu bar too: read when the panel opens, and by the welcome tour.
    func refreshBuiltInBatteryShown() {
        let shown = Self.readBuiltInBatteryShown()
        if shown != isBuiltInBatteryShown { isBuiltInBatteryShown = shown }
    }

    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        settingsWindow.show()
    }

    /// Settings › History, at an app's own history when a key (``BatteryHistory/AppIdentity/key``) is given.
    func openHistory(app key: String? = nil) {
        historyApp = key
        openSettings(.history)
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

    /// Why charging is paused or slow, when the panel can tell. It needs the panel's measurements (the Mac's power
    /// draw and the battery's readings), so it's only known while the panel is open. On battery there's nothing to
    /// say, and it returns before reading them, so the panel doesn't redraw each time they change.
    var chargingNote: ChargingNote? {
        guard battery.snapshot.isPluggedIn else { return nil }
        return ChargingNote.evaluate(
            snapshot: battery.snapshot, adapter: battery.adapter, systemWatts: usage.systemWatts, chargerWatts: usage.chargerWatts,
            readings: battery.readings)
    }

    /// The numbers behind the panel's estimates, for the current moment.
    var estimates: Estimates {
        Estimates(snapshot: battery.snapshot, systemWatts: usage.systemWatts)
    }
}
