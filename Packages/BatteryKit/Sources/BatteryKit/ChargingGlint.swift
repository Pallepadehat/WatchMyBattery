import Foundation

/// The menu bar's charging glint: a soft swell of light that leaves the edge
/// of the charge, rolls through the empty part of the battery to its
/// terminal, and fades as it gets there, which gives the terminal a flash.
///
/// Every frame costs the app real work: macOS redraws the status item and
/// re-snapshots it for each menu bar it appears in. So a sweep has only as
/// many frames as it needs to look smooth. It always had 26, at 24 a second,
/// however far the swell had to go; over a battery two-thirds charged that
/// moves it about ``maximumStep`` from one frame to the next. A fuller battery
/// leaves the swell only a few points to travel, so it now gets fewer frames,
/// just enough to keep to that step: as smooth, for up to 60% fewer frames.
/// An emptier one keeps all 26. Frames where nothing shows (the very start
/// and end of a sweep) are left out: they look just like the still icon.
///
/// When macOS charges only part way (Optimized Battery Charging holds it at
/// 80%), the swell rolls up to the target and settles there in a soft glow,
/// instead of running on to the terminal: charge flowing to where it's going.
public struct ChargingGlint: Equatable, Sendable {
    /// Where the glint is in one frame.
    public struct Frame: Equatable, Sendable {
        /// The swell's centre, from the left edge of the battery's body, in points.
        public var center: Double
        /// How wide the swell is, in points.
        public var width: Double
        /// How strongly the swell shows, 0–1.
        public var strength: Double
        /// How brightly the end of the sweep glows as the swell arrives, 0–1: the terminal, or the target line.
        public var flash: Double

        /// Nothing of it would show.
        public var isInvisible: Bool { strength < ChargingGlint.invisible && flash < ChargingGlint.invisible }
    }

    /// The glint at `phase` (0–1 through the sweep), on a battery body `bodyWidth` points wide, charged to `level`
    /// and charging to `target` (both 0–1).
    public static func frame(at phase: Double, bodyWidth: Double, level: Double, target: Double = 1) -> Frame {
        let phase = min(max(phase, 0), 1)
        let fill = fillWidth(bodyWidth: bodyWidth, level: level)
        let empty = emptyWidth(bodyWidth: bodyWidth, level: level, target: target)
        let width = swellWidth(emptyWidth: empty)
        // Ease in and out, so the swell glides rather than ticks.
        let t = phase < 0.5 ? 2 * phase * phase : 1 - pow(-2 * phase + 2, 2) / 2
        // The end lights up as the swell arrives.
        let arrival = min(max((phase - 0.55) / 0.45, 0), 1)
        return Frame(
            center: fill + travel(emptyWidth: empty, target: target) * t,
            width: width,
            // Fades in as it leaves the charge and out as it reaches the end.
            strength: sin(Double.pi * phase),
            flash: sin(Double.pi * arrival))
    }

    // MARK: - The frames of a sweep

    /// The longest a sweep lasts: 26 frames at 24 a second, as it always has.
    public static let sweepDuration: TimeInterval = 25.0 / 24
    /// The most frames a sweep gets.
    public static let maximumFrames = 26
    /// The fewest, so even a short sweep fades in and out rather than blinking.
    public static let minimumFrames = 10
    /// The furthest the swell moves between frames, in points.
    public static let maximumStep = 1.0
    /// Below this strength nothing shows: well under one step of an 8-bit alpha channel at the swell's brightest.
    static let invisible = 0.02

    /// The charge level the frames are for.
    public let level: Double
    /// The phase of each frame worth drawing, in order, 0–1.
    public let phases: [Double]
    /// The time between frames.
    public let frameInterval: TimeInterval

    /// The target the frames are for.
    public let target: Double

    public init(bodyWidth: Double, level: Double, target: Double = 1) {
        self.level = level
        self.target = target
        let travel = Self.travel(emptyWidth: Self.emptyWidth(bodyWidth: bodyWidth, level: level, target: target), target: target)
        // The swell moves fastest mid-sweep, at twice its average speed (the easing's steepest point).
        let needed = Int((2 * travel / Self.maximumStep).rounded(.up)) + 1
        let count = min(max(needed, Self.minimumFrames), Self.maximumFrames)
        frameInterval = Self.sweepDuration / Double(count - 1)
        phases = (0..<count).map { Double($0) / Double(count - 1) }.filter {
            !Self.frame(at: $0, bodyWidth: bodyWidth, level: level, target: target).isInvisible
        }
    }

    // MARK: - Geometry

    /// The charge always shows at least this wide, so an almost empty battery still reads as one.
    public static let minimumFillWidth = 3.0

    /// How wide the charge is drawn, in points.
    public static func fillWidth(bodyWidth: Double, level: Double) -> Double {
        level > 0 ? min(max(bodyWidth * level, minimumFillWidth), bodyWidth) : 0
    }

    /// The part of the battery the swell rolls through: from the charge to the target.
    static func emptyWidth(bodyWidth: Double, level: Double, target: Double = 1) -> Double {
        max(targetPosition(bodyWidth: bodyWidth, target: target) - fillWidth(bodyWidth: bodyWidth, level: level), 0)
    }

    /// Where the target is, from the left edge of the body, in points.
    public static func targetPosition(bodyWidth: Double, target: Double) -> Double {
        bodyWidth * min(max(target, 0), 1)
    }

    /// How far the swell's centre goes: off through the terminal when charging to full, to the target line otherwise.
    static func travel(emptyWidth: Double, target: Double) -> Double {
        target >= 1 ? emptyWidth + swellWidth(emptyWidth: emptyWidth) / 2 : emptyWidth
    }

    static func swellWidth(emptyWidth: Double) -> Double {
        max(min(emptyWidth * 0.7, 10), 5)
    }
}
