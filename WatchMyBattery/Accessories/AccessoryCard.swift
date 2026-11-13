import BatteryKit
import SwiftUI

/// The card that slides in when AirPods (or other headphones) connect: a
/// ring for each earbud and the case, filling up one after another as the
/// card appears, like on iPhone.
struct AccessoryCard: View {
    let accessory: Accessory
    /// Rings start empty and fill up; previews draw them full right away.
    var fillsOnAppear = true
    var close: () -> Void = {}
    var open: () -> Void = {}

    @State private var isFilled = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 328

    private var isShownFull: Bool { isFilled || !fillsOnAppear }

    var body: some View {
        VStack(spacing: 18) {
            header
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(accessory.displayParts.enumerated()), id: \.element.id) { index, part in
                    PartRing(part: part, symbol: accessory.symbols.symbol(for: part.role), isFilled: isShownFull)
                        .frame(maxWidth: .infinity)
                        .animation(fillAnimation(index), value: isFilled)
                }
            }
            .padding(.horizontal, accessory.displayParts.count == 1 ? 0 : 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(width: Self.width)
        .contentShape(.rect)
        .onTapGesture(perform: open)
        // A touch of depth as it lands, on top of the window sliding in.
        .scaleEffect(hasAppeared || !fillsOnAppear || reduceMotion ? 1 : 0.97, anchor: .top)
        .animation(.snappy(duration: 0.35), value: accessory.displayParts)
        .onAppear {
            guard fillsOnAppear else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { hasAppeared = true }
            // A beat after the card lands, so the eye catches the rings filling.
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.2)) { isFilled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(accessory.name) connected"))
        .accessibilityValue(accessory.displayParts.map(\.spokenDescription).joined(separator: ", "))
        .accessibilityAction(named: Text("Open the Panel"), open)
        .accessibilityAction(named: Text("Close"), close)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: accessory.symbols.device)
                .font(.system(size: 19))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(LinearGradient(colors: [.primary.opacity(0.12), .primary.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(accessory.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                // The model under a name of the owner's own ("Gym", Powerbeats Pro 2); otherwise just that it's connected.
                Group {
                    if let model = accessory.modelSubtitle {
                        Text(verbatim: model)
                    } else {
                        Text("Connected")
                    }
                }
                .lineLimit(1)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.primary.opacity(0.08), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    /// The rings fill one after another, left to right, with a little spring.
    private func fillAnimation(_ index: Int) -> Animation? {
        guard fillsOnAppear else { return nil }
        if reduceMotion { return .easeOut(duration: 0.2) }
        return .spring(response: 1.0, dampingFraction: 0.85).delay(Double(index) * 0.1)
    }
}

/// One battery: a ring around the part's symbol, then its level and name.
private struct PartRing: View {
    let part: Accessory.Part
    let symbol: String
    let isFilled: Bool

    private static let diameter: CGFloat = 64

    var body: some View {
        VStack(spacing: 7) {
            LevelRing(
                level: isFilled ? part.level : 0, color: AccessoryColor.of(part), lineWidth: 5.5, isCharging: part.isCharging,
                fillsCenter: true
            )
            .frame(width: Self.diameter, height: Self.diameter)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
            .overlay(alignment: .topTrailing) {
                if part.isCharging {
                    ChargingBadge()
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            VStack(spacing: 1) {
                Text(isFilled ? part.level : 0, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(part.isLow ? AnyShapeStyle(AccessoryColor.red) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText(value: isFilled ? part.level : 0))
                if let title = part.title {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A green bolt on the ring, set off from it by a thin ring of the card's own colour.
private struct ChargingBadge: View {
    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 8.5, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 19, height: 19)
            .background(
                Circle().fill(LinearGradient(colors: [AccessoryColor.green, AccessoryColor.green.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            )
            .padding(2)
            .background(.background.opacity(0.85), in: .circle)
    }
}
