import Foundation

/// How the menu bar's battery moves while it charges: chosen in Settings.
public enum ChargingMotionStyle: String, CaseIterable, Identifiable, Sendable {
    /// A soft swell of light rolls through the empty part to where it's charging to (``ChargingGlint``).
    case flow
    /// The charge is liquid: its edge ripples like a surface as it rises.
    case liquid
    /// Fine diagonal stripes glide through the part still to charge, like the classic Mac progress bar.
    case stripes

    public var id: Self { self }
}

/// How it moves for the last few percent, where charging slows to a trickle.
public enum TrickleMotionStyle: String, CaseIterable, Identifiable, Sendable {
    /// The liquid's surface slows to a gentle sway.
    case calmLiquid
    /// The edge of the charge pulses softly.
    case slowPulse

    public var id: Self { self }
}

/// How it moves while plugged in and holding its charge.
public enum HoldingMotionStyle: String, CaseIterable, Identifiable, Sendable {
    /// The liquid at rest: its surface tilts very slowly one way and the other.
    case stillWater
    /// The plug gives a soft double beat every few seconds.
    case heartbeat
    /// The charge dims a little and comes back, slowly (``Breathing``).
    case breathing

    public var id: Self { self }
}

/// What the menu bar's battery is doing, and so how it moves.
public enum MenuBarMotion: Hashable, Sendable {
    case flow(level: Double, target: Double)
    case liquid
    case stripes
    case calmLiquid
    case slowPulse
    case stillWater
    case heartbeat
    case breathing

    /// The motion for this moment, or `nil` when the battery should be still (on battery, or full).
    public init?(
        snapshot: BatterySnapshot, charging: ChargingMotionStyle, trickle: TrickleMotionStyle, holding: HoldingMotionStyle
    ) {
        switch snapshot.chargeState {
        case .charging where snapshot.isTrickleCharging:
            self = trickle == .calmLiquid ? .calmLiquid : .slowPulse
        case .charging:
            switch charging {
            case .flow: self = .flow(level: snapshot.level, target: Double(snapshot.chargeTarget) / 100)
            case .liquid: self = .liquid
            case .stripes: self = .stripes
            }
        case .notCharging:
            switch holding {
            case .stillWater: self = .stillWater
            case .heartbeat: self = .heartbeat
            case .breathing: self = .breathing
            }
        case .charged, .discharging:
            return nil
        }
    }

    /// Its frames and timing. Loops (liquid, stripes, still water) have no rest and repeat seamlessly; the others rest
    /// between cycles, when nothing is drawn at all.
    public var cycle: MotionCycle {
        switch self {
        case .flow(let level, let target):
            let glint = ChargingGlint(bodyWidth: MotionCycle.bodyWidth, level: level, target: target)
            return MotionCycle(phases: glint.phases, frameInterval: glint.frameInterval, rest: 1.9)
        case .liquid: return .loop(duration: LiquidSurface.chargingPeriod, framesPerSecond: 12)
        case .stripes: return .loop(duration: Stripes.period, framesPerSecond: 12)
        case .calmLiquid: return .loop(duration: LiquidSurface.calmPeriod, framesPerSecond: 9)
        case .slowPulse: return .burst(duration: EdgePulse.duration, framesPerSecond: 10, rest: EdgePulse.rest)
        case .stillWater: return .loop(duration: LiquidSurface.stillPeriod, framesPerSecond: 8)
        case .heartbeat: return .burst(duration: Heartbeat.duration, framesPerSecond: 15, rest: Heartbeat.rest)
        case .breathing: return MotionCycle(phases: Breathing.phases, frameInterval: Breathing.frameInterval, rest: Breathing.rest)
        }
    }
}

/// One cycle of a motion: the phase of each frame (0–1), the time between frames, and the rest after the cycle.
public struct MotionCycle: Equatable, Sendable {
    public let phases: [Double]
    public let frameInterval: TimeInterval
    public let rest: TimeInterval

    /// The width of the menu bar battery's body, in points, which the glint's frames are worked out for.
    public static let bodyWidth = 23.0

    /// A seamless loop: phases from 0 up to (not including) 1, as 1 is 0 again.
    static func loop(duration: TimeInterval, framesPerSecond: Double) -> MotionCycle {
        let count = max(Int((duration * framesPerSecond).rounded()), 2)
        return MotionCycle(phases: (0..<count).map { Double($0) / Double(count) }, frameInterval: duration / Double(count), rest: 0)
    }

    /// A burst, then a rest: phases strictly between 0 and 1, as both ends look like the still icon.
    static func burst(duration: TimeInterval, framesPerSecond: Double, rest: TimeInterval) -> MotionCycle {
        let count = max(Int((duration * framesPerSecond).rounded()), 2)
        return MotionCycle(phases: (1..<count).map { Double($0) / Double(count) }, frameInterval: duration / Double(count), rest: rest)
    }
}

// MARK: - The motions' shapes

/// The liquid's surface: how far the edge of the charge leans out (positive) or in at a height, in points.
public enum LiquidSurface {
    /// Charging: ripples running up the surface. The second ripple is twice as fast, so the loop is seamless.
    public static let chargingPeriod: TimeInterval = 1.6
    /// The last few percent: one slow, small ripple.
    public static let calmPeriod: TimeInterval = 4
    /// Holding: a slow tilt one way and back, with the faintest ripple.
    public static let stillPeriod: TimeInterval = 7

    /// Charging, at `y` points from the top of the battery's body, `phase` 0–1 through the loop.
    public static func charging(y: Double, phase: Double) -> Double {
        let angle = 2 * .pi * phase
        return 1.0 * sin(y * 0.9 - angle) + 0.45 * sin(y * 1.9 + 2 * angle)
    }

    /// The last few percent: smaller and slower.
    public static func calm(y: Double, phase: Double) -> Double {
        0.7 * sin(y * 0.8 - 2 * .pi * phase)
    }

    /// Holding: the surface tilts by up to 0.9 points at its ends, around its middle (`height` points tall).
    public static func still(y: Double, height: Double, phase: Double) -> Double {
        let angle = 2 * .pi * phase
        let tilt = 0.9 * sin(angle) * (y - height / 2) / (height / 2)
        return tilt + 0.3 * sin(y * 0.7 - angle)
    }
}

/// The stripes: how far they've slid, in points, at `phase`. They repeat every ``spacing`` points.
public enum Stripes {
    public static let spacing = 5.0
    /// Time for the stripes to slide one spacing: a steady, unhurried glide.
    public static let period: TimeInterval = 0.85

    public static func offset(at phase: Double) -> Double { spacing * phase }
}

/// The slow pulse: how brightly the edge of the charge glows, 0–1.
public enum EdgePulse {
    public static let duration: TimeInterval = 1.6
    public static let rest: TimeInterval = 0.9

    public static func strength(at phase: Double) -> Double {
        let wave = sin(.pi * min(max(phase, 0), 1))
        return wave * wave
    }
}

/// The heartbeat: how much the plug swells, as a scale over 1: a beat, and a smaller one just after.
public enum Heartbeat {
    public static let duration: TimeInterval = 0.6
    public static let rest: TimeInterval = 2.6

    public static func swell(at phase: Double) -> Double {
        let t = min(max(phase, 0), 1) * duration
        func beat(at start: Double, length: Double) -> Double {
            let x = (t - start) / length
            return x > 0 && x < 1 ? sin(.pi * x) : 0
        }
        return 0.18 * beat(at: 0, length: 0.24) + 0.11 * beat(at: 0.3, length: 0.24)
    }
}
