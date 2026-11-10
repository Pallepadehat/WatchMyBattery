import AppKit
import BatteryKit
import Observation

/// Owns the app's long-lived pieces and the actions that span them.
@Observable
final class AppModel {
    let settings = AppSettings()
    let battery = BatteryMonitor()
    let usage = AppUsageMonitor()
    let updater = Updater()
    let launchAtLogin = LaunchAtLogin()

    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(model: self)

    func start() {
        battery.start()
        updater.start()
    }

    /// The panel is open: start measuring which apps use energy.
    func panelDidOpen() {
        usage.maximumApps = settings.maximumApps
        usage.start()
    }

    func panelDidClose() {
        usage.stop()
    }

    func openSettings() {
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

/// Turns power readings into the times the panel shows.
struct Estimates {
    let snapshot: BatterySnapshot
    let systemWatts: Double?

    /// Time estimates only make sense while running on battery.
    var appliesToTime: Bool {
        snapshot.chargeState == .discharging && snapshot.timeRemaining != nil && systemWatts != nil
    }

    /// The share of the system's power draw an app is responsible for, 0–1.
    func share(of watts: Double) -> Double {
        guard let systemWatts, systemWatts > 0 else { return 0 }
        return min(watts / systemWatts, TimeEstimate.maximumShare)
    }

    /// How much battery time quitting apps that draw `watts` in total would give back.
    func timeGained(byQuitting watts: Double) -> TimeInterval {
        guard appliesToTime, let timeRemaining = snapshot.timeRemaining, let systemWatts else { return 0 }
        return TimeEstimate.timeGained(timeRemaining: timeRemaining, systemWatts: systemWatts, appWatts: watts)
    }
}
