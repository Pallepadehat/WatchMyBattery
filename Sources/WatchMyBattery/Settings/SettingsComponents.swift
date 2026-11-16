import AppKit
import BatteryKit
import SwiftUI

// The pieces every Settings pane is built from.

/// A row title with a coloured icon badge, the way System Settings labels its rows.
struct SettingLabel<Subtitle: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    let subtitle: Subtitle

    init(_ title: LocalizedStringKey, symbol: String, color: Color, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.subtitle = subtitle()
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingIcon(symbol: symbol, color: color, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension SettingLabel where Subtitle == EmptyView {
    init(_ title: LocalizedStringKey, symbol: String, color: Color) {
        self.init(title, symbol: symbol, color: color) { EmptyView() }
    }
}

/// A white symbol on a coloured rounded square, the way System Settings marks its rows and panes.
///
/// Symbols come in very different shapes (a wide battery, a tall bolt), so
/// each is sized to fit the same box rather than drawn at one point size:
/// that way a set of them looks even, like System Settings' sidebar.
struct SettingIcon: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    /// Our own menu bar battery, full; with "100" in it, like the app icon; and nearly empty.
    static let battery = "wmb.battery"
    static let batteryWithNumber = "wmb.battery.number"
    static let lowBattery = "wmb.battery.low"

    var body: some View {
        glyph
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(color.gradient)
                    // A hairline edge, so light colours hold their shape on a light background.
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                            .strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        if symbol.hasPrefix("wmb.battery") {
            // The same drawing as the menu bar icon, as a template so it takes the white.
            let low = symbol == Self.lowBattery
            let icon = BatteryIcon(
                snapshot: BatterySnapshot(
                    percentage: low ? 18 : 100, powerSource: .battery, chargeState: .discharging, timeRemaining: nil),
                percentageStyle: symbol == Self.batteryWithNumber ? .inside : .hidden, usesColor: false
            ).image()
            Image(nsImage: icon)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.82)
        } else {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
        }
    }

    /// The point size at which the symbol's longer side fills about 62% of the box.
    private var glyphSize: CGFloat {
        let natural = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.size ?? CGSize(width: 16, height: 16)
        // Symbols are measured at 13 pt by default.
        let longest = max(natural.width, natural.height, 1)
        return size * 0.62 * 13 / longest
    }
}

/// A small coloured icon before a caption.
struct InlineIconLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}

/// "20%": one level to be notified at, on or off.
struct LevelChip: View {
    let level: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Double(level) / 100, format: .percent)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.snappy(duration: 0.15), value: isOn)
    }
}

/// "Notifications are turned off for WatchMyBattery. [Open…]", when they are.
struct NotificationsDeniedRow: View {
    let notifier: LowBatteryNotifier

    var body: some View {
        if notifier.isDenied {
            LabeledContent {
                Button("Open…") { notifier.openNotificationSettings() }
            } label: {
                Label("Notifications are turned off for WatchMyBattery.", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(InlineIconLabelStyle(color: .orange))
                    .font(.caption)
            }
            .padding(.leading, 34)
        }
    }
}

/// "Needs Battery History, in Settings › Panel.", under a switch that does nothing without it.
struct NeedsHistoryNote: View {
    var body: some View {
        Label("Needs Battery History, in Settings › Panel.", systemImage: "info.circle.fill")
            .labelStyle(InlineIconLabelStyle(color: .secondary))
            .font(.caption)
            .padding(.leading, 34)
    }
}

extension View {
    /// Asks for permission to send notifications when a switch for one is turned on.
    func requestsNotifications(whenOn isOn: Bool, from notifier: LowBatteryNotifier) -> some View {
        onChange(of: isOn) { _, on in
            if on { Task { await notifier.requestAuthorization() } }
        }
    }
}
