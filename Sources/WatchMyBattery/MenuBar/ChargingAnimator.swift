import AppKit
import BatteryKit

/// Plays the charging glint: a short sweep across the battery, then a rest,
/// over and over, for as long as it's running.
///
/// It's built to cost next to nothing. Every frame makes macOS redraw the
/// status item and re-snapshot it for each menu bar it shows in, so a sweep
/// has only the frames it needs (``ChargingGlint`` picks them: fewer on a
/// fuller battery, where the glint has less far to go, and none where it
/// wouldn't show). Between sweeps nothing runs at all: no timer fires for
/// most of each cycle. The owner stops it whenever nobody could see it
/// (displays asleep, another user logged in) or it isn't wanted (Reduce
/// Motion, Low Power Mode, the setting turned off).
final class ChargingAnimator {
    /// Gets the glint's position, 0–1, for each frame, and `nil` when it rests or stops.
    var onFrame: ((Double?) -> Void)?

    private(set) var isRunning = false
    private var timer: Timer?
    private var frame = 0
    /// The charge level and target the sweep is for; new ones take effect from the next sweep.
    private var level = 0.5
    private var target = 1.0
    private var sweepFrames = ChargingGlint(bodyWidth: BatteryIcon.bodyWidth, level: 0.5)

    /// The most frames a sweep has, for showing them all (the previews).
    static let framesPerSweep = ChargingGlint.maximumFrames
    /// The pause between sweeps.
    private static let rest: TimeInterval = 1.9

    /// Starts sweeping over a battery charged to `level` and charging to `target` (both 0–1), or keeps going with new ones.
    func start(level: Double, target: Double = 1) {
        self.level = level
        self.target = target
        guard !isRunning else { return }
        isRunning = true
        sweep()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        onFrame?(nil)
    }

    private func sweep() {
        if level != sweepFrames.level || target != sweepFrames.target {
            sweepFrames = ChargingGlint(bodyWidth: BatteryIcon.bodyWidth, level: level, target: target)
        }
        frame = 0
        schedule(every: sweepFrames.frameInterval, repeats: true) { [weak self] in self?.advance() }
    }

    private func advance() {
        guard isRunning else { return }
        let phases = sweepFrames.phases
        if frame >= phases.count {
            timer?.invalidate()
            onFrame?(nil)
            schedule(every: Self.rest, repeats: false) { [weak self] in self?.sweep() }
            return
        }
        onFrame?(phases[frame])
        frame += 1
    }

    private func schedule(every interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        // A little slack lets macOS coalesce the wake-ups with others.
        timer.tolerance = repeats ? interval * 0.1 : 0.2
        // `.common`, so it keeps going while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
