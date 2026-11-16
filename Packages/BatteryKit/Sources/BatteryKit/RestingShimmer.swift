import Foundation

/// The menu bar's animation while the Mac is plugged in but holding its charge (at a charge limit, held by Optimized
/// Battery Charging, or resting near full): a soft sheen glides across the charge, from the left to its edge, and the
/// edge glows as it arrives, out towards where the battery is held. Then a rest.
///
/// It's the charging glint's opposite: charging, light flows into the empty part, where charge is going; holding,
/// it passes over the charge that's there, like light across a full glass. It's lighter, too: a sheen every four and
/// a half seconds, where the glint sweeps every three.
public enum RestingShimmer {
    /// Where the sheen is in one frame.
    public struct Frame: Equatable, Sendable {
        /// The sheen's centre, from the left edge of the charge, in points.
        public var center: Double
        /// How wide the sheen is, in points.
        public var width: Double
        /// How strongly it shows, 0–1.
        public var strength: Double
        /// How brightly the edge of the charge glows as the sheen reaches it, 0–1.
        public var glow: Double
    }

    /// How long one sheen lasts, from the left to the glow at the edge fading out.
    public static let duration: TimeInterval = 1.6
    /// The pause between sheens.
    public static let rest: TimeInterval = 2.9
    /// Frames in a sheen: enough that it glides rather than ticks across a full battery.
    static let frameCount = 22

    /// The time between frames.
    public static var frameInterval: TimeInterval { duration / Double(frameCount - 1) }

    /// The phase of each frame worth drawing, 0–1. The first and last look like the still icon, so they're left out.
    public static let phases: [Double] = (1..<(frameCount - 1)).map { Double($0) / Double(frameCount - 1) }

    /// The sheen at `phase` (0–1), over a charge `fillWidth` points wide.
    public static func frame(at phase: Double, fillWidth: Double) -> Frame {
        let phase = min(max(phase, 0), 1)
        let width = max(min(fillWidth * 0.45, 10), 5)
        // The sheen crosses in the first 70%, eased so it glides, and fades in and out as it goes.
        let crossing = min(phase / 0.7, 1)
        let eased = crossing < 0.5 ? 2 * crossing * crossing : 1 - pow(-2 * crossing + 2, 2) / 2
        // The edge glows as the sheen arrives, swelling and fading over the rest.
        let arrival = min(max((phase - 0.5) / 0.5, 0), 1)
        return Frame(
            center: -width / 2 + (fillWidth + width) * eased,
            width: width,
            strength: crossing < 1 ? sin(.pi * crossing) : 0,
            glow: sin(.pi * arrival))
    }
}
