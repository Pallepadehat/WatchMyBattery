import AppKit
import BatteryKit

/// Plays the menu bar icon's animation: a short cycle of frames, then a rest, over and over, for as long as it's
/// running. Charging, a glint sweeps across the battery towards where it's charging to; plugged in and holding its
/// charge, a sheen glides across the charge and its edge glows.
///
/// It's built to cost next to nothing. Every frame makes macOS redraw the
/// status item and re-snapshot it for each menu bar it shows in, so a cycle
/// has only the frames it needs (``ChargingGlint`` picks the glint's: fewer
/// on a fuller battery, where it has less far to go, and none where it
/// wouldn't show; ``RestingShimmer`` has 20). Between cycles nothing runs
/// at all: no timer fires for most of each one. The owner stops it whenever
/// nobody could see it (displays asleep, another user logged in) or it isn't
/// wanted (Reduce Motion, Low Power Mode, the setting turned off).
final class ChargingAnimator {
    /// What the icon is doing.
    enum Motion: Equatable {
        /// Charging from `level` to `target`, both 0–1.
        case charging(level: Double, target: Double)
        /// Plugged in, holding its charge.
        case resting
    }

    /// Gets the phase, 0–1, of each frame, and `nil` when it rests or stops.
    var onFrame: ((Double?) -> Void)?

    private(set) var isRunning = false
    private var timer: Timer?
    private var frame = 0
    /// What's playing; a new motion takes effect from the next cycle.
    private var motion = Motion.resting
    private var cycle = Cycle.resting

    /// The most frames a sweep has, for showing them all (the previews).
    static let framesPerSweep = ChargingGlint.maximumFrames

    /// Starts playing `motion`, or keeps going with it from the next cycle.
    func start(_ motion: Motion) {
        self.motion = motion
        guard !isRunning else { return }
        isRunning = true
        beginCycle()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        onFrame?(nil)
    }

    private func beginCycle() {
        if cycle.motion != motion { cycle = Cycle(motion) }
        frame = 0
        schedule(every: cycle.frameInterval, repeats: true) { [weak self] in self?.advance() }
    }

    private func advance() {
        guard isRunning else { return }
        if frame >= cycle.phases.count {
            timer?.invalidate()
            onFrame?(nil)
            schedule(every: cycle.rest, repeats: false) { [weak self] in self?.beginCycle() }
            return
        }
        onFrame?(cycle.phases[frame])
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

    /// One cycle's frames and timing, worked out once per motion.
    private struct Cycle {
        let motion: Motion
        let phases: [Double]
        let frameInterval: TimeInterval
        let rest: TimeInterval

        /// The pause between charging sweeps.
        private static let sweepRest: TimeInterval = 1.9

        init(_ motion: Motion) {
            self.motion = motion
            switch motion {
            case .charging(let level, let target):
                let glint = ChargingGlint(bodyWidth: BatteryIcon.bodyWidth, level: level, target: target)
                (phases, frameInterval, rest) = (glint.phases, glint.frameInterval, Self.sweepRest)
            case .resting:
                (phases, frameInterval, rest) = (RestingShimmer.phases, RestingShimmer.frameInterval, RestingShimmer.rest)
            }
        }

        static let resting = Cycle(.resting)
    }
}
