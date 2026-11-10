import AppKit
import BatteryKit
import Observation

/// Keeps ``snapshot`` up to date with the battery.
///
/// macOS notifies us when anything changes, so this costs nothing while the
/// battery sits still. Low Power Mode and waking from sleep are watched too,
/// as power source notifications don't cover them.
@Observable
final class BatteryMonitor {
    private(set) var snapshot = PowerSourceReader.read()

    @ObservationIgnored private var observer: PowerSourceObserver?
    @ObservationIgnored private var notificationTokens: [any NSObjectProtocol] = []

    func start() {
        guard observer == nil else { return }
        let observer = PowerSourceObserver { [weak self] in self?.refresh() }
        observer.start()
        self.observer = observer

        let onNotification: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        notificationTokens = [
            NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main, using: onNotification),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: onNotification),
        ]
        refresh()
    }

    func refresh() {
        let next = PowerSourceReader.read()
        // Only publish real changes, so views and the menu bar icon don't redraw for nothing.
        if next != snapshot { snapshot = next }
    }

    #if DEBUG
        /// Shows a made-up state, for previews.
        func preview(_ snapshot: BatterySnapshot) {
            self.snapshot = snapshot
        }
    #endif
}
