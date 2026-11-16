import AppKit
import BatteryKit

/// Plays the menu bar icon's motion (``MenuBarMotion``): the frames of one cycle, then its rest, over and over, for as
/// long as it's running. A loop (liquid, stripes, still water) has no rest and runs straight on from its last frame to
/// its first; the others rest between cycles, when nothing runs at all.
///
/// It's built to cost as little as it can. Every frame makes macOS redraw the
/// status item and re-snapshot it for each menu bar it shows in, so each
/// motion has only the frames it needs: the glint's are picked by
/// ``ChargingGlint`` (fewer on a fuller battery, none where it wouldn't
/// show), a slow fade gets nine a second. The owner stops it whenever nobody
/// could see it (displays asleep, another user logged in) or it isn't wanted
/// (Reduce Motion, Low Power Mode, the setting turned off).
final class ChargingAnimator {
    /// Gets the phase, 0–1, of each frame, and `nil` when it rests or stops.
    var onFrame: ((Double?) -> Void)?

    private(set) var isRunning = false
    private var timer: Timer?
    private var frame = 0
    /// What's playing; a new motion takes effect from the next cycle.
    private var motion = MenuBarMotion.breathing
    private var cycle = MenuBarMotion.breathing.cycle

    /// The most frames a glint sweep has, for showing them all (the previews).
    static let framesPerSweep = ChargingGlint.maximumFrames

    /// Starts playing `motion`. A running loop switches at once; anything else from its next cycle.
    func start(_ motion: MenuBarMotion) {
        let changed = motion != self.motion
        self.motion = motion
        guard !isRunning else {
            // A loop never rests, so it would never reach a next cycle to switch at: start the new motion now.
            if changed, cycle.rest == 0 { beginCycle() }
            return
        }
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
        cycle = motion.cycle
        frame = 0
        schedule(every: cycle.frameInterval, repeats: true) { [weak self] in self?.advance() }
    }

    private func advance() {
        guard isRunning else { return }
        if frame >= cycle.phases.count {
            guard cycle.rest > 0 else {
                // A loop: straight back to its first frame.
                frame = 0
                advance()
                return
            }
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
}
