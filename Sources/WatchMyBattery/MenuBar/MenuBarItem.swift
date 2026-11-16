import AppKit
import BatteryKit
import SwiftUI

/// What the menu bar shows for the battery: the icon in its style, and the text beside it. Shared by the status item
/// and the samples in Settings, so the two always agree.
struct MenuBarItem {
    var icon: BatteryIcon
    /// `84%`, `4:50` or `7.4 W`; `nil` for none.
    var text: String?

    init(snapshot: BatterySnapshot, settings: AppSettings, style: MenuBarIconStyle? = nil, watts: Double?, drawsForDarkBar: Bool? = nil) {
        let style = style ?? settings.menuBarIconStyle
        icon = BatteryIcon(
            snapshot: snapshot, style: style, showsPercentageInside: settings.showsPercentageInside, usesColor: settings.usesColor,
            drawsForDarkBar: drawsForDarkBar)
        text = MenuBarReadout(label: style.shownLabel(settings.menuBarLabel), snapshot: snapshot, watts: watts)?.text
        // Never leave nothing to click: text only, with no text (a Mac without a battery) and no glyph, shows the battery.
        if icon.isEmpty && text == nil { icon.style = .battery }
    }

    /// Text only puts its bolt in front of the text; otherwise the text leads, as macOS's own battery has it.
    var leadsWithIcon: Bool { icon.style == .textOnly }

    /// The text says the battery is low in red, when it's all there is to say so.
    var showsTextAsLow: Bool { icon.style == .textOnly && icon.accent == .low }
}

/// A ``MenuBarItem`` drawn in SwiftUI, laid out as the status item lays it out: for the samples in Settings and the
/// previews.
struct MenuBarItemView: View {
    let item: MenuBarItem

    var body: some View {
        let image = item.icon.isEmpty ? nil : item.icon.image()
        HStack(spacing: 4) {
            if item.leadsWithIcon, let image { icon(image) }
            if let text = item.text {
                Text(text)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(item.showsTextAsLow ? Color.red : Color.primary)
                    .contentTransition(.numericText())
            }
            if !item.leadsWithIcon, let image { icon(image) }
        }
    }

    private func icon(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
    }
}

extension MenuBarReadout {
    /// As the menu bar shows it: `84%`, `4:50` or `7.4 W`.
    var text: String {
        switch self {
        case .percentage(let percentage): (Double(percentage) / 100).formatted(.percent.precision(.fractionLength(0)))
        case .time(let interval): TimeFormat.clock(interval)
        case .watts(let watts): PowerFormat.watts(watts)
        }
    }
}
