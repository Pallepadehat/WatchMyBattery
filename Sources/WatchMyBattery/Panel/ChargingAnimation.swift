import SwiftUI

/// What the panel's battery animates: charge flowing in, or a battery plugged in and holding its charge.
enum ChargingMotion: Equatable {
    /// A wave of light rolls across, lighting the bolt as it passes.
    case charging
    /// A wide, soft light drifts slowly back and forth across the battery, and the plug glows as it passes: nothing
    /// flows in, the charge is just held.
    case resting
}

/// Where the panel's charging animation is: the wave of light rolling across
/// the battery, and the glow it lights the bolt with as it passes.
nonisolated struct ChargingPhase: Equatable, Sendable {
    /// The wave's position, 0 (off the left edge) to 1 (off the right edge).
    var wave: Double = 0
    /// How brightly the bolt (or the plug) glows, 0–1. It peaks as the wave reaches the middle.
    var glow: Double = 0
    /// How strongly the light shows, 0–1: full while charging, softer while resting.
    var intensity: Double = 1

    /// One cycle: a pause, the wave rolling across, the bolt lighting up as it passes.
    static let rest: TimeInterval = 0.6
    static let roll: TimeInterval = 2.0

    /// Resting: the light's drift from one side to the other, and how far towards each edge it goes.
    static let drift: TimeInterval = 3.4
    static let driftRange = 0.18...0.82
    static let restingIntensity = 0.8
}

private nonisolated struct ChargingPhaseKey: EnvironmentKey {
    static let defaultValue: ChargingPhase? = nil
}

extension EnvironmentValues {
    /// The charging animation's current frame, or `nil` when it isn't playing.
    nonisolated var chargingPhase: ChargingPhase? {
        get { self[ChargingPhaseKey.self] }
        set { self[ChargingPhaseKey.self] = newValue }
    }
}

extension View {
    /// Plays the charging animation for everything inside, which reads it from
    /// ``EnvironmentValues/chargingPhase``. A single repeating keyframe
    /// timeline drives the wave, the glow and the breath, so they stay in step.
    /// `nil` plays nothing.
    func chargingAnimation(_ motion: ChargingMotion?) -> some View {
        modifier(ChargingAnimationModifier(motion: motion))
    }
}

/// A modifier rather than code in the `View` extension, so the animation's
/// closures don't capture the generic view type, which isn't `Sendable`.
private struct ChargingAnimationModifier: ViewModifier {
    let motion: ChargingMotion?

    @ViewBuilder func body(content: Content) -> some View {
        switch motion {
        case .charging:
            content.keyframeAnimator(initialValue: ChargingPhase(), repeating: true) { content, phase in
                content.environment(\.chargingPhase, phase)
            } keyframes: { _ in
                KeyframeTrack(\.wave) {
                    LinearKeyframe(0, duration: ChargingPhase.rest)
                    CubicKeyframe(1, duration: ChargingPhase.roll)
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(0, duration: ChargingPhase.rest + ChargingPhase.roll * 0.3)
                    CubicKeyframe(1, duration: ChargingPhase.roll * 0.22)
                    CubicKeyframe(0, duration: ChargingPhase.roll * 0.48)
                }
            }
        case .resting:
            // Eased at each end, like a pendulum; dimmer towards the edges (``ChargingWave`` fades it there), and the
            // plug glows each time the light passes over it in the middle.
            let range = ChargingPhase.driftRange
            content.keyframeAnimator(
                initialValue: ChargingPhase(wave: range.lowerBound, intensity: ChargingPhase.restingIntensity), repeating: true
            ) { content, phase in
                content.environment(\.chargingPhase, phase)
            } keyframes: { _ in
                KeyframeTrack(\.wave) {
                    CubicKeyframe(range.upperBound, duration: ChargingPhase.drift)
                    CubicKeyframe(range.lowerBound, duration: ChargingPhase.drift)
                }
                // Over the plug on the way across, and again on the way back.
                KeyframeTrack(\.glow) {
                    CubicKeyframe(0.6, duration: ChargingPhase.drift / 2)
                    CubicKeyframe(0, duration: ChargingPhase.drift / 2)
                    CubicKeyframe(0.6, duration: ChargingPhase.drift / 2)
                    CubicKeyframe(0, duration: ChargingPhase.drift / 2)
                }
            }
        case nil:
            content
        }
    }
}

/// A soft glow of light rolling across the battery, left to right, like
/// charge flowing in. It matches the swell in the menu bar icon.
///
/// The light is a blurred ellipse, so it has no edges or bands, only a smooth
/// falloff. It's blurred once and then only moved, which is cheap to animate.
struct ChargingWave: View {
    /// The light's colour.
    let color: Color
    /// Adds light (on a dark or coloured battery) rather than laying a tint over it (on a white one).
    let brightens: Bool

    @Environment(\.chargingPhase) private var phase

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let wave = phase?.wave ?? 0
            // Brightest mid-way, fading in at the left and out at the right. Raised to a power, so it eases in from
            // nothing rather than appearing at the edge.
            let strength = pow(sin(Double.pi * wave), 1.6) * (phase?.intensity ?? 1)
            // It swells a little as it rolls through the middle, like a breath of charge.
            let glowWidth = size.width * (0.44 + 0.12 * strength)
            Ellipse()
                .fill(color.opacity((brightens ? 0.42 : 0.34) * strength))
                .frame(width: glowWidth, height: size.height * (1.05 + 0.15 * strength))
                .blur(radius: size.height * 0.32)
                .position(x: -glowWidth * 0.3 + (size.width + glowWidth * 0.6) * wave, y: size.height / 2)
                .blendMode(brightens ? .plusLighter : .normal)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Lights a symbol up as the wave passes: a glow around it and a slight swell.
struct ChargingGlow: ViewModifier {
    let color: Color

    @Environment(\.chargingPhase) private var phase

    func body(content: Content) -> some View {
        let glow = phase?.glow ?? 0
        content
            .scaleEffect(1 + 0.14 * glow)
            .shadow(color: color.opacity(0.9 * glow), radius: 7 * glow)
            .shadow(color: color.opacity(0.5 * glow), radius: 2 * glow)
    }
}
