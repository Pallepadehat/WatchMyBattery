import AppKit

/// Plays the charging glint: a short sweep across the battery, then a rest,
/// over and over, for as long as it's running.
///
/// It's built to cost next to nothing. The sweep is a handful of frames at a
/// modest frame rate, and between sweeps nothing runs at all: no timer fires
/// for most of each cycle. The owner stops it whenever nobody could see it
/// (displays asleep, another user logged in) or it isn't wanted (Reduce
/// Motion, Low Power Mode, the setting turned off).
final class ChargingAnimator {
    /// Gets the glint's position, 0–1, for each frame, and `nil` when it rests or stops.
    var onFrame: ((Double?) -> Void)?

    private(set) var isRunning = false
    private var timer: Timer?
    private var frame = 0

    /// One sweep: frames at ~24 per second, so a sweep takes just over a second.
    static let framesPerSweep = 26
    private static let frameInterval: TimeInterval = 1 / 24
    /// The pause between sweeps.
    private static let rest: TimeInterval = 1.9

    func start() {
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
        frame = 0
        schedule(every: Self.frameInterval, repeats: true) { [weak self] in self?.advance() }
    }

    private func advance() {
        guard isRunning else { return }
        if frame >= Self.framesPerSweep {
            timer?.invalidate()
            onFrame?(nil)
            schedule(every: Self.rest, repeats: false) { [weak self] in self?.sweep() }
            return
        }
        onFrame?(Double(frame) / Double(Self.framesPerSweep - 1))
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
