import AppKit
import BatteryKit
import Observation

/// Plays a chime when the charger is connected or disconnected, when that's turned on in Settings › Charging.
///
/// It listens to the battery snapshot, which changes by notification, so it costs nothing in between.
/// ``PowerChangeDetector`` decides which changes deserve a chime; a short wait before playing lets a loose cable's
/// flicker settle, so it never chimes for a state that's already gone.
final class ChargingChime {
    private weak var model: AppModel?
    private var detector = PowerChangeDetector()
    private var pending: Task<Void, Never>?
    private var sleepTokens: [any NSObjectProtocol] = []
    /// Each sound, made or loaded once.
    private var sounds: [String: NSSound] = [:]
    private var playing: NSSound?

    /// How long the new power source must hold before the chime plays.
    private static let settleTime: Duration = .milliseconds(300)

    func start(model: AppModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        sleepTokens = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.detector.willSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.detector.didWake(at: Date()) }
            },
        ]
        observe()
    }

    /// Plays the chime for `change` in `sound`: for Settings, to hear it before choosing.
    func play(_ change: PowerChange, sound: ChimeSound) {
        guard let next = self.sound(sound, for: change) else { return }
        playing?.stop()
        next.play()
        playing = next
    }

    private func observe() {
        guard let model else { return }
        let snapshot = withObservationTracking {
            model.battery.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        // Always update the detector, chime or not, so turning the chime on later doesn't chime for an old change.
        guard let change = detector.update(snapshot, at: Date()) else { return }
        let settings = model.settings
        guard settings.playsChargingChime, settings.chimeMoments.includes(change) else { return }

        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleTime)
            guard !Task.isCancelled, let self, let model = self.model else { return }
            guard model.battery.snapshot.isPluggedIn == (change == .pluggedIn) else { return }
            self.play(change, sound: model.settings.chimeSound)
        }
    }

    private func sound(_ sound: ChimeSound, for change: PowerChange) -> NSSound? {
        // WatchMyBattery's own chime rises or falls with the change; a system sound is the same either way.
        let key = sound == .watchMyBattery ? "\(sound.rawValue).\(change)" : sound.rawValue
        if let cached = sounds[key] { return cached }
        let made = sound == .watchMyBattery ? NSSound(data: ChimeSynth.wav(for: change)) : NSSound(named: sound.rawValue)
        sounds[key] = made
        return made
    }
}
