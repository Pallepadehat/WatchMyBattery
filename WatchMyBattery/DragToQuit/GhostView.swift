import SwiftUI

/// The app icon that follows the pointer while you drag it out of the panel.
struct GhostView: View {
    let state: GhostState

    var body: some View {
        ZStack {
            PoofView(trigger: state.poofCount, tint: state.tint)

            Image(nsImage: state.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .scaleEffect(state.isPoofing ? 1.6 : state.isArmed ? 0.92 : 1.06)
                .opacity(state.isPoofing ? 0 : state.isArmed ? 0.8 : 1)
                .blur(radius: state.isPoofing ? 8 : 0)

            Text("Quit \(state.name)")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.red.gradient, in: .capsule)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .scaleEffect(state.isArmed ? 1 : 0.7, anchor: .top)
                .opacity(state.isArmed && !state.isPoofing ? 1 : 0)
                .offset(y: 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A little cloud of smoke, like an icon dragged off the Dock.
private struct PoofView: View {
    let trigger: Int
    let tint: Color

    private struct Puff {
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
    }

    private struct Frame {
        var spread: CGFloat = 0
        var opacity: Double = 0
        var scale: CGFloat = 0.3
    }

    private static let puffs: [Puff] = (0..<10).map { index in
        let wobble = index.isMultiple(of: 2) ? 0.18 : -0.12
        return Puff(
            angle: Double(index) / 10 * 2 * .pi + wobble,
            distance: index.isMultiple(of: 2) ? 40 : 28,
            size: index.isMultiple(of: 3) ? 30 : 22)
    }

    var body: some View {
        ZStack {
            ForEach(Self.puffs.indices, id: \.self) { index in
                let puff = Self.puffs[index]
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .white.opacity(0.6), tint.opacity(0.25), .clear], center: .center,
                            startRadius: 0, endRadius: puff.size / 1.6))
                    .frame(width: puff.size, height: puff.size)
                    .keyframeAnimator(initialValue: Frame(), trigger: trigger) { content, frame in
                        content
                            .scaleEffect(frame.scale)
                            .offset(x: cos(puff.angle) * puff.distance * frame.spread, y: sin(puff.angle) * puff.distance * frame.spread)
                            .opacity(frame.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.spread) { CubicKeyframe(1, duration: 0.42) }
                        KeyframeTrack(\.scale) { CubicKeyframe(1.35, duration: 0.42) }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0.95, duration: 0.05)
                            CubicKeyframe(0, duration: 0.37)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}
