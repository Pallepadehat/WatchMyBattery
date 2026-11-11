import BatteryKit
import SwiftUI
import UniformTypeIdentifiers

/// The panes of Settings, in the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, menuBar, panel, notifications, updates, about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .panel: "Panel"
        case .notifications: "Notifications"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var titleString: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .panel: String(localized: "Panel")
        case .notifications: String(localized: "Notifications")
        case .updates: String(localized: "Updates")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .menuBar: "rectangle.topthird.inset.filled"
        case .panel: SettingIcon.battery
        case .notifications: "bell.fill"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .menuBar: .blue
        case .panel: .green
        case .notifications: .red
        case .updates: .indigo
        case .about: .orange
        }
    }
}

/// Settings, laid out like System Settings: a sidebar of panes, each a short grouped form.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $model.settingsPane) { pane in
                HStack(spacing: 8) {
                    SettingIcon(symbol: pane.symbol, color: pane.color, size: 22)
                    Text(pane.title)
                }
                .padding(.vertical, 2)
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch model.settingsPane ?? .general {
                case .general: GeneralPane(model: model)
                case .menuBar: MenuBarPane(model: model)
                case .panel: PanelPane(model: model)
                case .notifications: NotificationsPane(model: model)
                case .updates: UpdatesPane(model: model)
                case .about: AboutPane(model: model)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(model.settingsPane?.title ?? "General")
            // The title bar names the pane, as in System Settings.
            .background(WindowTitle(title: model.settingsPane?.titleString ?? ""))
        }
        .frame(minWidth: 700, idealWidth: 720, minHeight: 480, idealHeight: 560)
    }
}

/// Sets the title of the window it's in.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let title = title
        DispatchQueue.main.async { view.window?.title = title }
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    let model: AppModel
    @State private var language = AppLanguage.chosen

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.launchAtLogin.isEnabled }, set: { model.launchAtLogin.setEnabled($0) })) {
                    SettingLabel("Open at Login", symbol: "power", color: .gray) {
                        Text("Start WatchMyBattery when you log in.")
                    }
                }
                Picker(selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                } label: {
                    SettingLabel("Language", symbol: "globe", color: .blue)
                }
                .onChange(of: language) { _, language in AppLanguage.choose(language) }
                if language != AppLanguage.current {
                    LabeledContent {
                        Button("Relaunch Now") { AppLanguage.relaunch() }
                            .buttonStyle(.borderedProminent)
                    } label: {
                        Label("WatchMyBattery switches language when it opens again.", systemImage: "arrow.clockwise.circle.fill")
                            .labelStyle(InlineIconLabelStyle(color: .accentColor))
                            .font(.callout)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.snappy, value: language)

            Section {
                LabeledContent {
                    Button("Open…") { model.openControlCenterSettings() }
                } label: {
                    SettingLabel("Hide the Built-in Battery", symbol: "rectangle.topthird.inset.filled", color: .gray) {
                        Text("Control Center › Battery › Don't Show in Menu Bar")
                    }
                }
                LabeledContent {
                    Button("Open…") { model.openBatterySettings() }
                } label: {
                    SettingLabel("Battery Settings", symbol: SettingIcon.battery, color: .green) {
                        Text("Low Power Mode, battery health and charging, in System Settings.")
                    }
                }
            } header: {
                Text("macOS")
            }

            Section {
                LabeledContent {
                    Button("Quit") { NSApp.terminate(nil) }
                } label: {
                    SettingLabel("Quit WatchMyBattery", symbol: "power", color: .red) {
                        Text("Removes the battery from the menu bar until you open the app again.")
                    }
                }
            }
        }
    }
}

private struct MenuBarPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                PercentageStylePicker(snapshot: model.battery.snapshot, settings: settings)
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            } header: {
                Text("Percentage")
            }
            Section {
                Toggle(isOn: $settings.usesColor) {
                    SettingLabel("Colorful States", symbol: "paintpalette.fill", color: .orange) {
                        Text("Green while charging, yellow in Low Power Mode, red when low.")
                    }
                }
                Toggle(isOn: $settings.showsChargingAnimation) {
                    SettingLabel("Charging Animation", symbol: "bolt.fill", color: .green) {
                        Text("A soft glow flows into the battery while it charges, here and in the panel.")
                    }
                }
            } header: {
                Text("Look")
            }
            Section {
                LabeledContent {
                    ShortcutRecorder(model: model)
                } label: {
                    SettingLabel("Keyboard Shortcut", symbol: "command", color: .gray) {
                        if model.isPanelShortcutTaken {
                            Label("Another app uses this shortcut. Choose a different one.", systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(InlineIconLabelStyle(color: .orange))
                        } else {
                            Text("Opens and closes the panel from any app.")
                        }
                    }
                }
            } header: {
                Text("Panel")
            }
        }
    }
}

private struct PanelPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Picker(selection: $settings.centerLabel) {
                    ForEach(CenterLabel.allCases) { label in
                        Text(label.title).tag(label)
                    }
                } label: {
                    SettingLabel("Inside the Battery", symbol: SettingIcon.batteryWithNumber, color: .green)
                }
                Picker(selection: $settings.maximumApps) {
                    ForEach(AppSettings.appCountRange, id: \.self) { count in
                        Text(count.formatted()).tag(count)
                    }
                } label: {
                    SettingLabel("Apps Shown", symbol: "square.stack.3d.up.fill", color: .purple) {
                        Text("The apps using the most energy each get a slice.")
                    }
                }
            } header: {
                Text("Battery")
            }
            Section {
                Toggle(isOn: $settings.confirmsQuit) {
                    SettingLabel("Ask Before Quitting", symbol: "hand.raised.fill", color: .red) {
                        Text("When you drag an app out of the battery. Delete on a selected slice always asks.")
                    }
                }
                HiddenAppsRow(model: model)
            } header: {
                Text("Apps")
            } footer: {
                Text("Tip: press Tab to move between slices with the keyboard, and Delete to quit one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NotificationsPane: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                LowBatteryRows(model: model)
            }
        }
    }
}

private struct UpdatesPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var updater = model.updater
        Form {
            Section {
                UpdateCheckRow(updater: model.updater)
            }
            Section {
                Toggle(isOn: $updater.checksAutomatically) {
                    SettingLabel("Check for Updates Automatically", symbol: "arrow.triangle.2.circlepath", color: .blue) {
                        Text("Once a day. Nothing about you is sent.")
                    }
                }
                Toggle(isOn: $updater.downloadsAutomatically) {
                    SettingLabel("Install Updates Automatically", symbol: "square.and.arrow.down.fill", color: .blue)
                }
                .disabled(!updater.checksAutomatically)
            }
        }
    }
}

private struct AboutPane: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("WatchMyBattery")
                        .font(.system(size: 22, weight: .bold))
                    Text("Your battery, and who's draining it.")
                        .foregroundStyle(.secondary)
                    Text("Version \(model.updater.currentVersion)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section {
                AboutLink("Source Code on GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: "https://github.com/Pallepadehat/WatchMyBattery")
                AboutLink("What's New", symbol: "sparkles", url: "https://github.com/Pallepadehat/WatchMyBattery/blob/main/CHANGELOG.md")
                AboutLink("Report a Bug", symbol: "ladybug.fill", url: "https://github.com/Pallepadehat/WatchMyBattery/issues/new/choose")
            } footer: {
                if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
                    Text("\(copyright) · MIT License")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
        }
    }
}

private struct AboutLink: View {
    let title: LocalizedStringKey
    let symbol: String
    let url: String

    init(_ title: LocalizedStringKey, symbol: String, url: String) {
        self.title = title
        self.symbol = symbol
        self.url = url
    }

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
private struct SettingIcon: View {
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

// MARK: - Updates

/// "Check Now", with the answer right in the row: checking, up to date, a new version, or what went wrong.
private struct UpdateCheckRow: View {
    let updater: Updater

    var body: some View {
        LabeledContent {
            switch updater.checkState {
            case .checking:
                ProgressView().controlSize(.small)
            case .available:
                Button("Install…") { updater.installUpdate() }
                    .buttonStyle(.borderedProminent)
            default:
                Button("Check Now") { updater.checkNow() }
                    .disabled(!updater.canCheckForUpdates)
            }
        } label: {
            SettingLabel("Updates", symbol: "sparkles", color: .indigo) {
                status
                    .contentTransition(.opacity)
            }
        }
        .animation(.snappy, value: updater.checkState)
    }

    @ViewBuilder private var status: some View {
        switch updater.checkState {
        case .checking:
            Text("Checking for updates…")
        case .upToDate:
            Label("WatchMyBattery \(updater.currentVersion) is the latest version.", systemImage: "checkmark.circle.fill")
                .labelStyle(InlineIconLabelStyle(color: .green))
        case .available(let version):
            Label("Version \(version) is available.", systemImage: "arrow.down.circle.fill")
                .labelStyle(InlineIconLabelStyle(color: .accentColor))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(InlineIconLabelStyle(color: .orange))
                .lineLimit(2)
        case .idle:
            if let lastCheck = updater.lastCheck {
                Text("Version \(updater.currentVersion) · Last checked \(lastCheck, format: .relative(presentation: .named))")
            } else {
                Text("Version \(updater.currentVersion)")
            }
        }
    }
}

/// A small coloured icon before a caption.
private struct InlineIconLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}

// MARK: - Keyboard shortcut

/// Shows the panel's shortcut; click it, then press the keys for a new one. Escape cancels, Delete clears.
private struct ShortcutRecorder: View {
    let model: AppModel
    @State private var isRecording = false
    @State private var monitor: Any?
    /// The last key press couldn't be a shortcut, because it had no ⌘, ⌥ or ⌃.
    @State private var needsModifier = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(title)
                    .monospacedDigit()
                    .frame(minWidth: 110)
                    .foregroundStyle(isRecording ? Color.accentColor : model.settings.panelShortcut == nil ? .secondary : .primary)
            }
            .help(isRecording ? "Press Escape to cancel, or Delete to remove the shortcut." : "Click, then press the keys you want.")
            if model.settings.panelShortcut != nil, !isRecording {
                Button {
                    model.setPanelShortcut(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove the shortcut")
                .accessibilityLabel("Remove the shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var title: String {
        if isRecording { return needsModifier ? String(localized: "Add ⌘, ⌥ or ⌃") : String(localized: "Type Shortcut…") }
        return model.settings.panelShortcut?.displayString ?? String(localized: "Record Shortcut")
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        needsModifier = false
        model.pausePanelShortcut()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let plain = event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        if plain && event.keyCode == 53 {  // Escape
            stopRecording()
        } else if plain && (event.keyCode == 51 || event.keyCode == 117) {  // Delete, Forward Delete
            model.setPanelShortcut(nil)
            stopRecording()
        } else if let hotkey = Hotkey(event: event) {
            model.setPanelShortcut(hotkey)
            stopRecording()
        } else {
            needsModifier = true
            NSSound.beep()
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { model.registerPanelShortcut() }
        isRecording = false
        needsModifier = false
    }
}

// MARK: - Hidden apps

/// Apps that never get a slice of the battery, with buttons to add and remove them.
private struct HiddenAppsRow: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Button("Add…", action: add)
            } label: {
                SettingLabel("Hidden Apps", symbol: "eye.slash.fill", color: .gray) {
                    Text("Never shown in the battery, so they can't be quit by accident.")
                }
            }
            if !model.settings.excludedApps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.settings.excludedApps, id: \.self) { bundleIdentifier in
                        HiddenAppItem(bundleIdentifier: bundleIdentifier) {
                            withAnimation(.snappy) { model.removeExclusion(bundleIdentifier) }
                        }
                    }
                }
                .padding(.leading, 34)
            }
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Hide")
        panel.message = String(localized: "Choose apps that should never get a slice of the battery.")
        guard panel.runModal() == .OK else { return }
        withAnimation(.snappy) {
            for url in panel.urls {
                if let bundleIdentifier = Bundle(url: url)?.bundleIdentifier {
                    model.settings.exclude(bundleIdentifier: bundleIdentifier)
                }
            }
            model.usage.excludedApps = Set(model.settings.excludedApps)
        }
    }
}

private struct HiddenAppItem: View {
    let bundleIdentifier: String
    let remove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleIdentifier)
                .lineLimit(1)
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show in the battery again")
            .accessibilityLabel("Show in the battery again")
        }
        .padding(.vertical, 3)
        .transition(.opacity)
    }
}

// MARK: - Low battery

/// The low battery notification: on or off, and at which levels.
private struct LowBatteryRows: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.notifiesWhenLow) {
            SettingLabel("Low Battery", symbol: SettingIcon.lowBattery, color: .red) {
                Text("A notification naming the app using the most energy, with a button to quit it.")
            }
        }
        .onChange(of: settings.notifiesWhenLow) { _, on in
            if on { Task { await model.notifier.requestAuthorization() } }
        }
        .task { await model.notifier.refreshAuthorization() }

        if settings.notifiesWhenLow {
            LabeledContent("Notify At") {
                HStack(spacing: 4) {
                    ForEach(AppSettings.lowBatteryChoices.reversed(), id: \.self) { level in
                        LevelChip(level: level, isOn: settings.lowBatteryLevels.contains(level)) {
                            toggle(level)
                        }
                    }
                }
            }
            .padding(.leading, 34)

            if model.notifier.isDenied {
                LabeledContent {
                    Button("Open…") { model.notifier.openNotificationSettings() }
                } label: {
                    Label("Notifications are turned off for WatchMyBattery.", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(InlineIconLabelStyle(color: .orange))
                        .font(.caption)
                }
                .padding(.leading, 34)
            }
        }
    }

    private func toggle(_ level: Int) {
        var levels = Set(model.settings.lowBatteryLevels)
        if levels.contains(level) {
            // Keep at least one, or the switch above would be on for nothing.
            guard levels.count > 1 else { return }
            levels.remove(level)
        } else {
            levels.insert(level)
        }
        model.settings.lowBatteryLevels = levels.sorted(by: >)
    }
}

/// "20%": one level to be notified at, on or off.
private struct LevelChip: View {
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
        let icon = BatteryIcon(
            snapshot: snapshot, percentageStyle: style, usesColor: settings.usesColor, drawsForDarkBar: wallpaper.isDark
        ).image()
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
