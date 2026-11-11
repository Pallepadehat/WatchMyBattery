import BatteryKit
import SwiftUI

/// "Charging  62% → 80%", over a bar: the charge so far, the part
/// still to come with light flowing towards the target, and a notch where
/// macOS will stop. When Optimized Battery Charging holds the battery short
/// of full, the part past the target is hatched: that's charge it's holding
/// back on purpose, to make the battery last longer.
struct ChargeProgressRow: View {
    let snapshot: BatterySnapshot
    let usesColor: Bool
    /// Play the flowing light (the panel is open, the setting is on, nothing asks for less motion).
    let animates: Bool

    /// Charging, or holding at a target short of full: the bar has something to say.
    static func applies(to snapshot: BatterySnapshot) -> Bool {
        snapshot.isCharging || (snapshot.chargeState == .notCharging && snapshot.hasChargeLimit && snapshot.isAtTarget)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                if snapshot.isAtTarget {
                    // Held on purpose: say why, rather than repeat the level.
                    Label("Optimized", systemImage: "leaf.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(usesColor ? ChargeTrack.green : .secondary)
                } else {
                    HStack(spacing: 4) {
                        Text(percent(snapshot.percentage))
                            .contentTransition(.numericText(value: Double(snapshot.percentage)))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(percent(snapshot.chargeTarget))
                            .fontWeight(.semibold)
                    }
                    .monospacedDigit()
                }
            }
            .font(.system(size: 12))

            ChargeTrack(
                level: snapshot.level, target: Double(snapshot.chargeTarget) / 100, isCharging: snapshot.isCharging,
                tint: tint, animates: animates && snapshot.isCharging
            )
            .frame(height: 8)
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text("Now \(percent(snapshot.percentage)), charging to \(percent(snapshot.chargeTarget))"))
    }

    private var title: LocalizedStringKey {
        // The target is on the right and in the time row below, so the title doesn't repeat it while charging.
        snapshot.isCharging ? "Charging" : "Holding at \(percent(snapshot.chargeTarget))"
    }

    private var help: Text {
        snapshot.hasChargeLimit
            ? Text(
                "Optimized Battery Charging keeps the battery at \(percent(snapshot.chargeTarget)) for now, so it lasts longer, and finishes charging in time for when you usually unplug."
            )
            : Text("Charging to 100%.")
    }

    private var tint: Color {
        usesColor ? ChargeTrack.green : .primary
    }

    private func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The bar itself. Static parts are plain shapes; only the light moves, and only while charging with the panel open.
struct ChargeTrack: View {
    let level: Double
    let target: Double
    let isCharging: Bool
    let tint: Color
    let animates: Bool

    static let green = Color(red: 0.2, green: 0.78, blue: 0.35)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let fillEnd = max(width * min(level, 1), height)
            let targetX = width * min(max(target, 0), 1)

            ZStack(alignment: .leading) {
                // The whole battery, faint.
                Capsule().fill(.quaternary)

                // Past the target: held back on purpose, so hatched rather than empty.
                if target < 1 {
                    HeldBackHatching()
                        .frame(width: width - targetX)
                        .offset(x: targetX)
                }

                // Still to come: a soft tint from the charge to the target, with light flowing along it.
                if isCharging, targetX > fillEnd {
                    Rectangle()
                        .fill(tint.opacity(0.18))
                        .frame(width: targetX - fillEnd)
                        .overlay {
                            if animates { ChargeFlow(color: tint) }
                        }
                        .offset(x: fillEnd)
                }

                // The charge so far, with a little glow at its leading edge while it grows.
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillEnd)
                    .shadow(color: isCharging ? tint.opacity(0.45) : .clear, radius: 3)
            }
            .clipShape(.capsule)
            .overlay(alignment: .leading) {
                // The target: a notch standing just proud of the bar.
                if target < 1 {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: height + 6)
                        .offset(x: targetX - 1)
                        .shadow(color: tint.opacity(isCharging ? 0 : 0.6), radius: 3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Light flowing towards the target, in step with the battery's charging wave (it reads the same timeline).
private struct ChargeFlow: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let spot = max(min(width * 0.6, 60), 16)
            // Starts behind the edge of the charge and runs off at the target, brightest mid-way.
            KeyframeAnimator(initialValue: 0.0, repeating: true) { progress in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0), color.opacity(0.65 * sin(.pi * progress)), color.opacity(0)],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: spot)
                    .offset(x: -spot + (width + spot) * progress)
            } keyframes: { _ in
                LinearKeyframe(0, duration: ChargingPhase.rest)
                CubicKeyframe(1, duration: ChargingPhase.roll)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Fine diagonal lines: charge the battery could take but is holding back.
private struct HeldBackHatching: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            var x = -size.height
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 4
            }
            context.stroke(lines, with: .style(.secondary.opacity(0.35)), lineWidth: 1)
        }
    }
}
