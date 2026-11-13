import BatteryKit
import Foundation
import OSLog
import Observation

/// Holds the battery at a level you choose, with macOS's own Charge Limit (see ``ChargeLimitClient``).
///
/// macOS does the holding, so the limit stays put whether WatchMyBattery runs or not, through restarts and
/// updates, and System Settings › Battery shows the same thing. WatchMyBattery only ever asks for a level macOS
/// offers (80% to 100%, in fives, today).
///
/// "Charge to Full Once" lifts the limit for one charge, for a day away from a charger, and puts it back as soon as
/// the Mac is unplugged.
@Observable
final class ChargeLimit {
    /// This Mac has a charge limit WatchMyBattery can set. `false` until checked.
    private(set) var isSupported = false
    /// The levels macOS offers, lowest first.
    private(set) var choices: [Int] = []
    /// The limit macOS holds the battery to; 100 means none.
    private(set) var limit = 100
    /// Waiting for macOS to take a change.
    private(set) var isChanging = false
    /// The last change didn't take.
    private(set) var failure: String?

    @ObservationIgnored private let client = ChargeLimitClient()
    @ObservationIgnored private weak var model: AppModel?

    /// Charging is held short of full.
    var isLimited: Bool { isSupported && limit < ChargeLimitClient.Levels.noLimit }

    /// Charging to 100% this once, with ``ChargeLimit/isLimited`` coming back on unplugging.
    var isToppingUp: Bool { (model?.settings.chargeLimitAfterTopUp ?? 0) > 0 }

    func start(model: AppModel) {
        self.model = model
        refresh()
        observe()
    }

    /// Reads the limit again: when the panel opens, as it can be changed in System Settings too.
    func refresh() {
        let client = client
        Task.detached(priority: .utility) {
            let levels = client.levels()?.choices ?? []
            let current = client.current()
            await MainActor.run { self.apply(choices: levels, current: current) }
        }
    }

    private func apply(choices: [Int], current: Int?) {
        let supported = !choices.isEmpty && current != nil
        if supported != isSupported { isSupported = supported }
        if choices != self.choices { self.choices = choices }
        if let current, current != limit { limit = current }
        model?.battery.chargeLimit = isLimited ? limit : nil
    }

    /// Asks macOS to hold the battery at `level`; 100 lifts the limit.
    func set(_ level: Int) {
        guard isSupported, !isChanging, choices.contains(level), level != limit || isToppingUp else { return }
        // Choosing a limit by hand ends a one-off charge to full.
        model?.settings.chargeLimitAfterTopUp = 0
        change(to: level)
    }

    /// Charges to 100% this once; the limit comes back when the Mac is unplugged.
    func chargeToFullOnce() {
        guard isLimited, let model else { return }
        model.settings.chargeLimitAfterTopUp = limit
        change(to: ChargeLimitClient.Levels.noLimit)
    }

    /// Puts the limit back now rather than on unplugging.
    func cancelTopUp() {
        guard let model, model.settings.chargeLimitAfterTopUp > 0 else { return }
        let level = model.settings.chargeLimitAfterTopUp
        model.settings.chargeLimitAfterTopUp = 0
        change(to: level)
    }

    private func change(to level: Int) {
        let previous = limit
        isChanging = true
        failure = nil
        // Shown right away; put back if macOS says no.
        limit = level
        model?.battery.chargeLimit = level < ChargeLimitClient.Levels.noLimit ? level : nil
        let client = client
        Task.detached(priority: .userInitiated) {
            var failure: String?
            do {
                try client.set(level)
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                self.isChanging = false
                if let failure {
                    Logger.app.error("Couldn't set the charge limit to \(level): \(failure, privacy: .public)")
                    self.failure = failure
                    self.limit = previous
                } else {
                    Logger.app.notice("Charge limit set to \(level)")
                }
                self.refresh()
            }
        }
    }

    /// Unplugged after a one-off charge to full: the limit comes back.
    private func observe() {
        guard let model else { return }
        let isPluggedIn = withObservationTracking {
            model.battery.snapshot.isPluggedIn
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        if !isPluggedIn, model.settings.chargeLimitAfterTopUp > 0, !isChanging {
            cancelTopUp()
        }
    }

    #if DEBUG
        /// Shows a limit without asking macOS, for previews.
        func preview(limit: Int, choices: [Int] = [80, 85, 90, 95, 100]) {
            isSupported = true
            self.choices = choices
            self.limit = limit
        }
    #endif
}
