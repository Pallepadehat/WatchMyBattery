import BatteryKit
import SwiftUI

// MARK: - Menu bar style

/// Three menu bars side by side, one per icon style, each with the text you chose; click one to choose it. In
/// Settings › Menu Bar and the welcome tour alike.
struct MenuBarStylePicker: View {
    let snapshot: BatterySnapshot
    @Bindable var settings: AppSettings
    let watts: Double?
    @State private var wallpaper = Wallpaper()

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MenuBarIconStyle.allCases) { style in
                Button {
                    withAnimation(.snappy) { settings.menuBarIconStyle = style }
                } label: {
                    VStack(spacing: 8) {
                        MenuBarSample(snapshot: snapshot, settings: settings, style: style, watts: watts, wallpaper: wallpaper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: settings.menuBarIconStyle == style ? 2.5 : 0)
                                    .padding(-3)
                            )
                        Text(style.title)
                            .font(.caption)
                            .foregroundStyle(settings.menuBarIconStyle == style ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(settings.menuBarIconStyle == style ? .isSelected : [])
            }
        }
        .task { await wallpaper.load() }
    }
}

/// A slice of menu bar over your own desktop picture, showing the battery in one style, laid out as the menu bar
/// lays it out.
private struct MenuBarSample: View {
    let snapshot: BatterySnapshot
    let settings: AppSettings
    let style: MenuBarIconStyle
    let watts: Double?
    let wallpaper: Wallpaper

    var body: some View {
        MenuBarItemView(
            item: MenuBarItem(snapshot: snapshot, settings: settings, style: style, watts: watts, drawsForDarkBar: wallpaper.isDark)
        )
        .foregroundStyle(wallpaper.isDark ? Color.white : Color.black)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background {
            if let image = wallpaper.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(white: 0.2)
            }
        }
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, wallpaper.isDark ? .dark : .light)
    }
}
