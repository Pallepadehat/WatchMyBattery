import Foundation

/// How a plugged-in battery that's holding its charge (at a charge limit, held by Optimized Battery Charging, or
/// resting near full) moves: it breathes. The charge dims a little and comes back, slowly, then rests, like the
/// sleep light Macs used to have. Nothing flows in, so nothing travels; it only lives.
///
/// The menu bar and the panel share this one curve, so they breathe together.
public enum Breathing {
    /// Breathing out (dimming) is quicker than breathing back in, the way the sleep light's was.
    public static let exhale: TimeInterval = 1.5
    public static let inhale: TimeInterval = 2.5
    /// Still, at full brightness, between breaths.
    public static let rest: TimeInterval = 2

    /// One breath, out and in.
    public static var duration: TimeInterval { exhale + inhale }

    /// How far the charge dims at the deepest point of a breath, 0–1. Enough to see, never enough to look empty.
    public static let depth = 0.2

    /// How deep into the breath it is at `phase` (0–1 through `duration`): 0 at full brightness, 1 at the deepest.
    /// Eased at both ends, so it never ticks into motion or stops with a jolt.
    public static func dimming(at phase: Double) -> Double {
        let t = min(max(phase, 0), 1) * duration
        if t <= exhale { return smoothstep(t / exhale) }
        return 1 - smoothstep((t - exhale) / inhale)
    }

    // MARK: - The menu bar's frames

    /// Frames a second while breathing: a slow fade needs few to look smooth.
    static let framesPerSecond = 9.0

    /// The time between frames.
    public static var frameInterval: TimeInterval { 1 / framesPerSecond }

    /// The phase of each frame, 0–1, leaving out the ends, which look like the still icon.
    public static let phases: [Double] = {
        let count = Int((duration * framesPerSecond).rounded())
        return (1..<count).map { Double($0) / Double(count) }
    }()

    private static func smoothstep(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
