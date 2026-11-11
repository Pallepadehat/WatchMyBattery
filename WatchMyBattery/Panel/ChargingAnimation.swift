import SwiftUI

/// Where the panel's charging animation is: the wave of light rolling across
/// the battery, and the glow it lights the bolt with as it passes.
nonisolated struct ChargingPhase: Equatable, Sendable {
    /// The wave's position, 0 (off the left edge) to 1 (off the right edge).
    var wave: Double = 0
    /// How brightly the bolt glows, 0–1. It peaks as the wave reaches the middle.
    var glow: Double = 0

    /// One cycle: a pause, the wave rolling across, the bolt lighting up as it passes.
    static let rest: TimeInterval = 0.6
    static let roll: TimeInterval = 2.0
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
    /// timeline drives both the wave and the glow, so they stay in step.
    func chargingAnimation(_ isOn: Bool) -> some View {
        modifier(ChargingAnimationModifier(isOn: isOn))
    }
}

/// A modifier rather than code in the `View` extension, so the animation's
/// closures don't capture the generic view type, which isn't `Sendable`.
private struct ChargingAnimationModifier: ViewModifier {
    let isOn: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if isOn {
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
        } else {
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
            let strength = pow(sin(Double.pi * wave), 1.6)
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
