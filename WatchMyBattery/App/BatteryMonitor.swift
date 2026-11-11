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
    /// Condition, maximum capacity and cycle count; `nil` until first read, or on Macs without a battery.
    private(set) var health: BatteryHealth?

    @ObservationIgnored private var healthReadAt: Date?
    @ObservationIgnored private var isReadingHealth = false
    /// Health changes over months, so a few hours between readings is plenty.
    private static let healthMaxAge: TimeInterval = 6 * 3600

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
        var next = PowerSourceReader.read()
        #if DEBUG
            // `--pretend-charging` shows the battery charging, to see the charging animation on a full battery.
            if CommandLine.arguments.contains("--pretend-charging") {
                next = BatterySnapshot(
                    percentage: 62, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 48 * 60,
                    isLowPowerModeOn: next.isLowPowerModeOn)
            }
        #endif
        // Only publish real changes, so views and the menu bar icon don't redraw for nothing.
        if next != snapshot { snapshot = next }
    }

    /// Reads battery health in the background, unless a recent reading is at hand.
    func refreshHealthIfNeeded() {
        guard snapshot.hasBattery, !isReadingHealth else { return }
        if let healthReadAt, Date().timeIntervalSince(healthReadAt) < Self.healthMaxAge { return }
        isReadingHealth = true
        Task { [weak self] in
            let health = await BatteryHealthReader.read()
            guard let self else { return }
            self.isReadingHealth = false
            self.healthReadAt = Date()
            if health != self.health { self.health = health }
        }
    }

    #if DEBUG
        /// Shows a made-up state, for previews.
        func preview(_ snapshot: BatterySnapshot, health: BatteryHealth? = nil) {
            self.snapshot = snapshot
            self.health = health
            healthReadAt = Date()
        }
    #endif
}
