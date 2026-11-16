import Foundation

/// The menu bar's animation while the Mac is plugged in but holding its charge (at a charge limit, held by Optimized
/// Battery Charging, or resting near full): a slow, soft breath of light at the edge of the charge, then a long rest.
///
/// Calmer than the charging glint, which rolls charge in, and cheaper: a dozen frames every five seconds or so,
/// where the glint has up to 26 every three. Nothing is flowing, so nothing moves; it only glows and fades.
public enum RestingBreath {
    /// How long one breath lasts, in and out.
    public static let duration: TimeInterval = 1.5
    /// The pause between breaths.
    public static let rest: TimeInterval = 3.5
    /// Frames in a breath: a soft glow changes slowly, so few are needed.
    static let frameCount = 13

    /// The time between frames.
    public static var frameInterval: TimeInterval { duration / Double(frameCount - 1) }

    /// The phase of each frame worth drawing, 0–1, leaving out the ends, where the breath doesn't show.
    public static let phases: [Double] = (0..<frameCount).map { Double($0) / Double(frameCount - 1) }.filter { strength(at: $0) >= 0.02 }

    /// How brightly it glows at `phase`, 0–1: easing in from nothing and back out, like a breath.
    public static func strength(at phase: Double) -> Double {
        let wave = sin(.pi * min(max(phase, 0), 1))
        return wave * wave
    }
}
