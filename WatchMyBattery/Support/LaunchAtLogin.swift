import Observation
import OSLog
import ServiceManagement

/// Opens WatchMyBattery when you log in, through a login item that shows up
/// in System Settings › General › Login Items.
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.app.error("Couldn't change the login item: \(error.localizedDescription, privacy: .public)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// The user may have changed it in System Settings since.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
