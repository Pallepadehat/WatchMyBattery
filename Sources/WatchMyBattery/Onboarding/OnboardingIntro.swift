import SwiftUI

/// The onboarding's opening: a green circle blooms, small dots gather and fly out, rings draw themselves, grid and
/// diagonal lines sweep in, and it all settles into the logo at the top, with the content rising in under it.
///
/// The logo then stays at the top of every step, shrinking to make room once the welcome has been read
/// (`compactLogo`). With Reduce Motion, it skips straight to the settled logo.
struct OnboardingIntro<Logo: View, Content: View>: View {
    var foregroundColor: Color = .white
    var tint: Color
    /// The steps after the welcome need the room: the logo shrinks.
    var compactLogo: Bool
    /// Start settled, as with Reduce Motion: for the previews.
    var skipsOpening = false
    @ViewBuilder var logo: (_ isSettled: Bool) -> Logo
    @ViewBuilder var content: (_ isSettled: Bool) -> Content
    var onClose: () -> Void

    @State private var properties = Properties()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var size: CGSize { CGSize(width: 460, height: 640) }
    private static var cornerRadius: CGFloat { 30 }

    var body: some View {
        let settled = properties.convertToLogo
        let layout = settled ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(ZStackLayout(alignment: .bottom))
        let logoSize: CGFloat = compactLogo ? 64 : 150

        layout {
            ZStack {
                // The bloom the opening plays on, fading as it settles, so the app's icon shows as itself.
                Circle()
                    .fill(tint.gradient)
                    .scaleEffect(properties.animateMainCircle ? 2 : 0)
                    .opacity(properties.convertToLogo ? 0 : 1)

                gridLines
                circles
                circleStrokes
                diagonalLines

                logo(settled)
                    // Sized to the logo's square, as the rings and lines around it are far larger.
                    .frame(width: settled ? logoSize : 220, height: settled ? logoSize : 220)
                    .compositingGroup()
                    .blur(radius: settled ? 0 : 50)
                    .opacity(settled ? 1 : 0)
            }
            // The opening fills the window, just inside its edge; then it settles into the logo.
            .frame(width: settled ? logoSize : Self.size.width - 20, height: settled ? logoSize : Self.size.height - 20)
            .padding(.bottom, settled ? 0 : 10)
            .clipShape(.rect(cornerRadius: settled ? logoSize * 0.28 : Self.cornerRadius, style: .continuous))
            .padding(.top, settled ? 28 : 0)
            .contentShape(.rect)
            .accessibilityHidden(true)

            content(settled)
                .visualEffect { content, proxy in
                    content.offset(y: settled ? 0 : proxy.size.height)
                }
                .opacity(settled ? 1 : 0)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .overlay(alignment: .topLeading) { closeButton }
        .modifier(OnboardingWindowBackground(cornerRadius: Self.cornerRadius))
        .animation(.bouncy(duration: 0.45, extraBounce: 0), value: compactLogo)
        .onAppear(perform: play)
    }

    // MARK: - The opening

    private func play() {
        guard !properties.animateMainCircle else { return }
        guard !reduceMotion, !skipsOpening else {
            properties.animateMainCircle = true
            properties.convertToLogo = true
            return
        }
        Task {
            await step(after: 0.1, .easeInOut(duration: 0.5)) { properties.animateMainCircle = true }
            await step(after: 0.15, .bouncy(duration: 0.35, extraBounce: 0.2)) { properties.circleScale = 1 }
            await step(after: 0.3, .bouncy(duration: 0.5)) { properties.circleOffset = 50 }
            await step(after: 0.1, .bouncy(duration: 0.4)) { properties.circleSize = 5 }
            await step(after: 0.25, .linear(duration: 0.4)) { properties.positionCircles = true }
            await step(after: 0.35, .linear(duration: 1)) { properties.animateStrokes = true }
            await step(after: 0.3, .linear(duration: 0.6)) { properties.animateGridLines = true }
            await step(after: 0.15, .linear(duration: 0.5)) { properties.animateDiagonalLines = true }
            await step(after: 0.5, .bouncy(duration: 0.5, extraBounce: 0)) { properties.convertToLogo = true }
        }
    }

    private func step(after delay: Double, _ animation: Animation, perform action: @escaping () -> Void) async {
        try? await Task.sleep(for: .seconds(delay))
        withAnimation(animation, action)
    }

    // MARK: - Its pieces

    /// Four dots that gather in the middle, fly out round it, and vanish as the rings draw.
    private var circles: some View {
        ZStack {
            ForEach(1...4, id: \.self) { index in
                let rotation = (CGFloat(index) / 4) * 360
                let extraRotation: CGFloat = properties.positionCircles ? 20 : 0
                let extraOffset: CGFloat = index % 2 != 0 ? 40 : -20
                Circle()
                    .fill(foregroundColor)
                    .frame(width: properties.circleSize, height: properties.circleSize)
                    .animation(.easeInOut(duration: 0.05).delay(0.35)) {
                        $0.scaleEffect(properties.positionCircles ? 0 : 1)
                    }
                    .offset(x: properties.positionCircles ? 120 + extraOffset : properties.circleOffset)
                    .rotationEffect(.degrees(rotation + extraRotation))
                    .animation(.easeInOut(duration: 0.2).delay(0.2)) {
                        $0.rotationEffect(.degrees(properties.positionCircles ? 12 : 0))
                    }
            }
        }
        .compositingGroup()
        .scaleEffect(properties.circleScale)
    }

    /// A small ring in the middle and four large ones round it, drawing themselves in.
    private var circleStrokes: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: properties.animateStrokes ? 1 : 0)
                .stroke(foregroundColor, lineWidth: 1)
                .frame(width: 70, height: 70)
                .scaleEffect(properties.convertToLogo ? 2.5 : 1)

            ForEach(1...4, id: \.self) { index in
                let rotation = (CGFloat(index) / 4) * 360
                let extraOffset: CGFloat = index % 2 != 0 ? 120 : 0
                Circle()
                    .trim(from: 0, to: properties.animateStrokes ? 1 : 0)
                    .stroke(foregroundColor.opacity(index >= 3 ? 0.3 : 1), lineWidth: 1)
                    .frame(width: 200 + extraOffset, height: 200 + extraOffset)
                    .rotationEffect(.degrees(rotation + 32))
            }
        }
        .compositingGroup()
        .scaleEffect(properties.convertToLogo ? 1.5 : 1)
        .opacity(properties.convertToLogo ? 0 : 1)
    }

    /// A five-by-five grid of faint lines, growing from alternate ends.
    private var gridLines: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Rectangle()
                        .fill(foregroundColor.tertiary)
                        .frame(width: 1, height: properties.animateGridLines ? nil : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .scaleEffect(y: index == 2 || index == 4 ? -1 : 1)
                }
            }
            VStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Rectangle()
                        .fill(foregroundColor.tertiary)
                        .frame(width: properties.animateGridLines ? nil : 0, height: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .scaleEffect(x: index == 2 || index == 4 ? -1 : 1)
                }
            }
        }
        .compositingGroup()
        .opacity(properties.convertToLogo ? 0 : 1)
    }

    /// Two long diagonals crossing the middle.
    private var diagonalLines: some View {
        ZStack {
            ForEach([-39.0, 39.0], id: \.self) { angle in
                Rectangle()
                    .fill(foregroundColor.tertiary)
                    .frame(width: 1, height: properties.animateDiagonalLines ? nil : 0)
                    .padding(.vertical, -100)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .rotationEffect(.degrees(angle))
            }
        }
        .compositingGroup()
        .opacity(properties.convertToLogo ? 0 : 1)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .padding(15)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .accessibilityLabel("Close")
        .opacity(properties.convertToLogo ? 1 : 0)
    }

    /// Each stage of the opening.
    private struct Properties {
        var animateMainCircle = false
        var circleSize: CGFloat = 50
        var circleOffset: CGFloat = 0
        var circleScale: CGFloat = 0
        var positionCircles = false
        var animateStrokes = false
        var animateGridLines = false
        var animateDiagonalLines = false
        var convertToLogo = false
    }
}

/// The onboarding window's rounded background: opaque, like macOS's own setup screens, so its text reads clearly
/// over any desktop picture (glass would let a busy one show through), with a hairline edge.
struct OnboardingWindowBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color(nsColor: .windowBackgroundColor), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1))
    }
}
