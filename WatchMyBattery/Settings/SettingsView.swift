import BatteryKit
import SwiftUI

/// Settings, laid out like a pane of System Settings.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        @Bindable var updater = model.updater

        Form {
            Section {
                AppHeader(version: model.updater.currentVersion)
            }

            Section {
                PercentageStylePicker(snapshot: model.battery.snapshot, settings: settings)
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
                Toggle(isOn: $settings.usesColor) {
                    SettingLabel("Colorful States", symbol: "paintpalette.fill", color: .orange) {
                        Text("Green while charging, yellow in Low Power Mode, red when low.")
                    }
                }
                LabeledContent {
                    Button("Open…") { model.openControlCenterSettings() }
                } label: {
                    SettingLabel("Hide the Built-in Battery", symbol: "menubar.rectangle", color: .gray) {
                        Text("Control Center › Battery › Don't Show in Menu Bar")
                    }
                }
            } header: {
                Text("Menu Bar")
            }

            Section("Panel") {
                Picker(selection: $settings.centerLabel) {
                    ForEach(CenterLabel.allCases) { label in
                        Text(label.title).tag(label)
                    }
                } label: {
                    SettingLabel("Inside the Battery", symbol: "battery.75percent", color: .green)
                }
                Picker(selection: $settings.maximumApps) {
                    ForEach(AppSettings.appCountRange, id: \.self) { count in
                        Text(count.formatted()).tag(count)
                    }
                } label: {
                    SettingLabel("Apps Shown", symbol: "square.stack.3d.up.fill", color: .purple)
                }
                Toggle(isOn: $settings.confirmsQuit) {
                    SettingLabel("Ask Before Quitting", symbol: "hand.raised.fill", color: .red) {
                        Text("When you drag an app out of the battery.")
                    }
                }
            }

            Section("General") {
                Toggle(isOn: Binding(get: { model.launchAtLogin.isEnabled }, set: { model.launchAtLogin.setEnabled($0) })) {
                    SettingLabel("Open at Login", symbol: "power", color: .gray)
                }
            }

            Section {
                Toggle(isOn: $updater.checksAutomatically) {
                    SettingLabel("Check for Updates Automatically", symbol: "arrow.triangle.2.circlepath", color: .blue)
                }
                Toggle(isOn: $updater.downloadsAutomatically) {
                    SettingLabel("Install Updates Automatically", symbol: "arrow.down.circle.fill", color: .blue)
                }
                .disabled(!updater.checksAutomatically)
                LabeledContent {
                    Button("Check Now") { model.updater.checkNow() }
                        .disabled(!model.updater.canCheckForUpdates)
                } label: {
                    SettingLabel("Updates", symbol: "sparkles", color: .indigo) {
                        if let lastCheck = model.updater.lastCheck {
                            Text("Last checked \(lastCheck, format: .relative(presentation: .named))")
                        } else {
                            Text("Version \(model.updater.currentVersion)")
                        }
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                HStack {
                    Link(destination: URL(string: "https://github.com/Pallepadehat/WatchMyBattery")!) {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Spacer()
                    Button("Quit WatchMyBattery") { NSApp.terminate(nil) }
                        .buttonStyle(.link)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 460)
        .frame(minHeight: 420, idealHeight: 560, maxHeight: .infinity)
    }
}

// MARK: - Header

/// The app's icon, name and version, like the top of an About pane.
private struct AppHeader: View {
    let version: String

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("WatchMyBattery")
                    .font(.system(size: 17, weight: .semibold))
                Text("Your battery, and who's draining it.")
                    .foregroundStyle(.secondary)
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rows

/// A row title with a coloured icon badge, the way System Settings labels its rows.
private struct SettingLabel<Subtitle: View>: View {
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
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color.gradient, in: .rect(cornerRadius: 6, style: .continuous))
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

// MARK: - Percentage style

/// Three menu bars side by side, one per percentage style; click one to choose it.
private struct PercentageStylePicker: View {
    let snapshot: BatterySnapshot
    @Bindable var settings: AppSettings
    @State private var wallpaper = Wallpaper()

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PercentageStyle.allCases) { style in
                Button {
                    withAnimation(.snappy) { settings.percentageStyle = style }
                } label: {
                    VStack(spacing: 8) {
                        MenuBarSample(snapshot: snapshot, settings: settings, style: style, wallpaper: wallpaper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: settings.percentageStyle == style ? 2.5 : 0)
                                    .padding(-3)
                            )
                        Text(style.title)
                            .font(.caption)
                            .foregroundStyle(settings.percentageStyle == style ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(settings.percentageStyle == style ? .isSelected : [])
            }
        }
        .task { await wallpaper.load() }
    }
}

/// A slice of menu bar over your own desktop picture, showing the battery in one style.
private struct MenuBarSample: View {
    let snapshot: BatterySnapshot
    let settings: AppSettings
    let style: PercentageStyle
    let wallpaper: Wallpaper

    var body: some View {
        let icon = BatteryIcon(snapshot: snapshot, percentageStyle: style, usesColor: settings.usesColor).image()
        HStack(spacing: 4) {
            if style == .beside {
                Text(snapshot.level, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
            Image(nsImage: icon)
                .renderingMode(icon.isTemplate ? .template : .original)
        }
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
