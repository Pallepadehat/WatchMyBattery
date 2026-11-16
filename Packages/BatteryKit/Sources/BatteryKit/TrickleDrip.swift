import Foundation

/// The menu bar's animation while the battery charges its last little bit (see ``BatterySnapshot/isTrickleCharging``):
/// a small drop of light swells at the edge of the charge, then drips in and fades, again and again. A trickle, where
/// the charging glint is a flow, and the resting shimmer is stillness.
public enum TrickleDrip {
    /// Where the drop is in one frame.
    public struct Frame: Equatable, Sendable {
        /// How far past the edge of the charge the drop's centre is, in points: it gathers just outside, then drips
        /// into the charge.
        public var offset: Double
        /// The drop's size, in points.
        public var size: Double
        /// How strongly it shows, 0–1.
        public var strength: Double
        /// How brightly the edge of the charge glows as the drop falls in, 0–1.
        public var glow: Double
    }

    /// One drop, from gathering to fading.
    public static let duration: TimeInterval = 1.2
    /// The pause between drops: short, so they keep coming, as a trickle does.
    public static let rest: TimeInterval = 1.1
    /// About 25 frames a second, so the drop swells and falls smoothly.
    static let frameCount = 30

    public static var frameInterval: TimeInterval { duration / Double(frameCount - 1) }

    /// The phase of each frame worth drawing, 0–1, leaving out the ends, which look like the still icon.
    public static let phases: [Double] = (1..<(frameCount - 1)).map { Double($0) / Double(frameCount - 1) }

    /// The drop at `phase`, 0–1.
    public static func frame(at phase: Double) -> Frame {
        let phase = min(max(phase, 0), 1)
        // It gathers outside the edge for the first half, swelling; then falls in, shrinking, and the edge glows.
        let gathering = min(phase / 0.5, 1)
        let falling = min(max((phase - 0.5) / 0.5, 0), 1)
        let fall = falling * falling * (3 - 2 * falling)
        return Frame(
            offset: 2.5 - 4.5 * fall,
            size: 2 + 2.5 * sin(.pi / 2 * gathering) - 1.5 * fall,
            strength: sin(.pi / 2 * gathering) * (1 - fall),
            glow: sin(.pi * falling))
    }
}
