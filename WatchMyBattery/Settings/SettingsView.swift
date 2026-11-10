import BatteryKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        @Bindable var updater = model.updater
        Form {
            Section {
                MenuBarPreview(snapshot: model.battery.snapshot, settings: model.settings)
                    .listRowInsets(EdgeInsets())
            }

            Section("Menu Bar") {
                Picker("Percentage", selection: $settings.percentageStyle) {
                    ForEach(PercentageStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle(isOn: $settings.usesColor) {
                    Text("Colorful states")
                    Text("Green while charging, yellow in Low Power Mode, red when low.")
                }
                LabeledContent {
                    Button("Open Control Center Settings") { model.openControlCenterSettings() }
                } label: {
                    Text("Hide the built-in battery")
                    Text("Control Center › Battery › Don't Show in Menu Bar")
                }
            }

            Section("Panel") {
                Picker("Center of the battery", selection: $settings.centerLabel) {
                    ForEach(CenterLabel.allCases) { label in
                        Text(label.title).tag(label)
                    }
                }
                Stepper(value: $settings.maximumApps, in: AppSettings.appCountRange) {
                    LabeledContent("Apps shown", value: model.settings.maximumApps.formatted())
                }
                Toggle(isOn: $settings.confirmsQuit) {
                    Text("Ask before quitting")
                    Text("When you drag an app out of the panel.")
                }
            }

            Section("General") {
                Toggle(
                    "Open at login",
                    isOn: Binding(get: { model.launchAtLogin.isEnabled }, set: { model.launchAtLogin.setEnabled($0) }))
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                Toggle("Download and install updates automatically", isOn: $updater.downloadsAutomatically)
                    .disabled(!model.updater.checksAutomatically)
                LabeledContent {
                    Button("Check Now") { model.updater.checkNow() }
                        .disabled(!model.updater.canCheckForUpdates)
                } label: {
                    Text("Version \(model.updater.currentVersion)")
                    if let lastCheck = model.updater.lastCheck {
                        Text("Last checked \(lastCheck, format: .relative(presentation: .named))")
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                HStack {
                    Link("WatchMyBattery on GitHub", destination: URL(string: "https://github.com/Pallepadehat/WatchMyBattery")!)
                    Spacer()
                    Button("Quit WatchMyBattery") { NSApp.terminate(nil) }
                }
                .font(.callout)
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// How the menu bar will look, on a light and a dark menu bar.
private struct MenuBarPreview: View {
    let snapshot: BatterySnapshot
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            bar(.light)
            bar(.dark)
        }
        .frame(height: 64)
    }

    private func bar(_ scheme: ColorScheme) -> some View {
        let icon = BatteryIcon(snapshot: snapshot, settings: settings)
        return HStack(spacing: 5) {
            if settings.percentageStyle == .beside {
                Text(snapshot.level, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 13))
                    .monospacedDigit()
            }
            Image(nsImage: icon.image())
                .renderingMode(icon.image().isTemplate ? .template : .original)
        }
        .foregroundStyle(scheme == .dark ? .white : .black)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.12, green: 0.14, blue: 0.32), Color(red: 0.2, green: 0.1, blue: 0.4)]
                    : [Color(red: 0.75, green: 0.85, blue: 1), Color(red: 0.9, green: 0.85, blue: 1)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, scheme)
        .animation(.snappy, value: settings.percentageStyle)
    }
}
