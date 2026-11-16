import BatteryKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The panes of Settings, in the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, menuBar, panel, charging, sleep, accessories, notifications, updates, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .panel: String(localized: "Panel")
        case .charging: String(localized: "Charging")
        case .sleep: String(localized: "Sleep")
        case .accessories: String(localized: "Accessories")
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
        case .charging: "powerplug.fill"
        case .sleep: "moon.zzz.fill"
        case .accessories: "airpodspro"
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
        case .charging: Color(red: 0.2, green: 0.74, blue: 0.62)
        case .sleep: .purple
        case .accessories: .cyan
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
            let pane = model.settingsPane ?? .general
            Group {
                switch pane {
                case .general: GeneralPane(model: model)
                case .menuBar: MenuBarPane(model: model)
                case .panel: PanelPane(model: model)
                case .charging: ChargingPane(model: model)
                case .sleep: SleepPane(model: model)
                case .accessories: AccessoriesPane(model: model)
                case .notifications: NotificationsPane(model: model)
                case .updates: UpdatesPane(model: model)
                case .about: AboutPane(model: model)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
            // The title bar names the pane, as in System Settings.
            .background(WindowTitle(title: pane.title))
        }
        .frame(width: Self.size.width)
        .frame(minHeight: Self.size.height, maxHeight: .infinity)
    }

    /// The window's one size: wide enough for a row and its subtitle, tall enough for most panes without scrolling.
    static let size = CGSize(width: 720, height: 560)
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
                if model.lowPowerMode.isSupported, model.lowPowerMode.helperState != .unavailable {
                    LowPowerModeHelperRow(lowPowerMode: model.lowPowerMode)
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
                MenuBarStylePicker(snapshot: model.battery.snapshot, settings: settings, watts: model.powerDraw.watts)
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
                Picker(selection: $settings.menuBarLabel) {
                    ForEach(MenuBarLabel.allCases) { label in
                        // Text only always shows some text, so "Nothing" isn't a choice there.
                        if label != .none || settings.menuBarIconStyle != .textOnly {
                            Text(label.title).tag(label)
                        }
                    }
                } label: {
                    SettingLabel(settings.menuBarIconStyle == .textOnly ? "Text" : "Beside the Icon", symbol: "textformat", color: .blue) {
                        Text(labelSubtitle(settings.effectiveMenuBarLabel))
                    }
                }
                if settings.menuBarIconStyle == .battery {
                    Toggle(isOn: $settings.showsPercentageInside) {
                        SettingLabel("Percentage Inside the Battery", symbol: SettingIcon.batteryWithNumber, color: .green) {
                            Text("Printed in the battery, cut out of the charge so it reads on any wallpaper.")
                        }
                    }
                    .transition(.opacity)
                }
            } header: {
                Text("Style")
            }
            .animation(.snappy, value: settings.menuBarIconStyle)
            .onChange(of: settings.menuBarIconStyle) { _, style in
                // "Nothing" isn't offered with text only; keep the picker on what it shows.
                if style == .textOnly, settings.menuBarLabel == .none { settings.menuBarLabel = .percentage }
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

    private func labelSubtitle(_ label: MenuBarLabel) -> LocalizedStringKey {
        switch label {
        case .none: "Just the icon."
        case .percentage: "How charged the battery is."
        case .timeRemaining: "Until empty, or until full while charging. The percentage when there's no time to show."
        case .powerDraw: "What the whole Mac draws right now, read every few seconds while it's shown."
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
                Toggle(isOn: $settings.showsSystemSlice) {
                    SettingLabel("Display & System", symbol: "sun.max.fill", color: .gray) {
                        Text("A slice for the power no app accounts for: the screen, graphics, Wi‑Fi, Bluetooth and macOS itself.")
                    }
                }
                Toggle(isOn: $settings.showsBatteryReadings) {
                    SettingLabel("Temperature, Voltage and Current", symbol: "thermometer.medium", color: .orange) {
                        Text("What the battery controller measures, under the battery.")
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
            Section {
                HistoryRows(model: model)
                HistoryKeepRows(model: model)
                Toggle(isOn: $settings.showsInsights) {
                    SettingLabel("Insights", symbol: "lightbulb.fill", color: .yellow) {
                        Text("A line in the panel when the battery won't last through a meeting, the Mac uses more power than usual, or a new app uses a lot.")
                    }
                }
                .disabled(!settings.recordsHistory && !settings.warnsBeforeMeetings)
            } header: {
                Text("History")
            }
        }
    }
}

/// How to get an iPhone or iPad to show up, once over a cable and then over Wi‑Fi for good. Folded away until asked
/// for.
private struct DeviceSetupSteps: View {
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                step(
                    "cable.connector", color: .gray, title: "Connect it once",
                    detail: "Plug it into this Mac with a cable, unlock it, and tap Trust.")
                step(
                    "macwindow", color: .blue, title: "Turn on Wi‑Fi in Finder",
                    detail: "Select it in Finder's sidebar. On the General tab, turn on “Show this iPhone when on Wi‑Fi” and click Apply.")
                step(
                    "wifi", color: .green, title: "Unplug it",
                    detail: "It now shows up whenever it's on the same Wi‑Fi as this Mac and awake.")
                Button("Open Finder") {
                    NSWorkspace.shared.open(URL(filePath: "/System/Library/CoreServices/Finder.app"))
                }
                .padding(.leading, 34)
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
        } label: {
            Text("How to Show Your iPhone or iPad")
                .foregroundStyle(.secondary)
        }
    }

    private func step(_ symbol: String, color: Color, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SettingIcon(symbol: symbol, color: color, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AccessoriesPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let accessories = model.accessories.accessories
        Form {
            Section {
                if accessories.isEmpty {
                    Text("No accessories with a battery are connected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accessories) { accessory in
                        AccessoryRow(accessory: accessory, monitor: model.accessories)
                    }
                }
            } header: {
                Text("Connected")
            } footer: {
                Text("AirPods, Beats and other headphones, the Magic Mouse, Keyboard and Trackpad, game controllers, and your iPhone and iPad.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.showsAccessoryCard) {
                    SettingLabel("AirPods Card", symbol: "airpodspro", color: .cyan) {
                        Text("Slides in below the menu bar when AirPods or other headphones connect, with the battery of each earbud and the case.")
                    }
                }
                if settings.showsAccessoryCard {
                    Picker("Position", selection: $settings.accessoryCardPosition) {
                        ForEach(AccessoryCardPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .padding(.leading, 34)
                    Picker("Stays For", selection: $settings.accessoryCardDuration) {
                        ForEach(AppSettings.accessoryCardDurations, id: \.self) { seconds in
                            Text(Duration.seconds(seconds), format: .units(allowed: [.seconds], width: .wide)).tag(seconds)
                        }
                    }
                    .padding(.leading, 34)
                    LabeledContent {
                        Button("Show Card") { model.showAccessoryCard(previewHeadphones) }
                    } label: {
                        Text("Stays while the pointer is over it. Click it to open the panel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 34)
                }
            } header: {
                Text("When Headphones Connect")
            }
            .animation(.snappy, value: settings.showsAccessoryCard)

            Section {
                Toggle(isOn: $settings.showsAccessories) {
                    SettingLabel("Accessories in the Panel", symbol: "list.bullet", color: .gray) {
                        Text("Under the battery, each with the level of every part.")
                    }
                }
                Toggle(isOn: Binding(get: { settings.showsDevices }, set: { model.setShowsDevices($0) })) {
                    SettingLabel("iPhone and iPad", symbol: "iphone", color: .blue) {
                        Text("Their battery, next to your accessories.")
                    }
                }
                // Until one shows up, how to get it there.
                if settings.showsDevices, !accessories.contains(where: { $0.kind == .phone || $0.kind == .tablet }) {
                    DeviceSetupSteps()
                }
            } footer: {
                Text("An Apple Watch only talks to its iPhone, so a Mac can't read its battery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The headphones that are connected, or a pair of AirPods Pro to show what the card looks like.
    private var previewHeadphones: Accessory {
        model.accessories.accessories.first { $0.kind.isAudio }
            ?? Accessory(
                id: "preview", name: "AirPods Pro", kind: .earbuds,
                parts: [.init(role: .left, percentage: 84), .init(role: .right, percentage: 84), .init(role: .case, percentage: 61, isCharging: true)],
                productID: 0x2027, vendorID: 0x004C)
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
                SupportCard()
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

/// "Enjoying WatchMyBattery?": a friendly way to support the app, with a button to Buy Me a Coffee.
private struct SupportCard: View {
    private static let url = URL(string: "https://buymeacoffee.com/patrickjakobsen")!
    /// Buy Me a Coffee's own yellow, so the button reads as theirs at a glance.
    private static let coffeeYellow = Color(red: 1, green: 0.867, blue: 0)

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Enjoying WatchMyBattery?")
                    .font(.headline)
                Text("It's free and open source, made in my spare time. If it helps your battery last, a coffee helps me keep making it better.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Link(destination: Self.url) {
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .rotationEffect(.degrees(isHovered ? -12 : 0))
                    Text("Buy Me a Coffee")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Self.coffeeYellow, in: .capsule)
                .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .shadow(color: Self.coffeeYellow.opacity(isHovered ? 0.55 : 0.25), radius: isHovered ? 8 : 4, y: 2)
                .scaleEffect(isHovered ? 1.04 : 1)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.snappy(duration: 0.2)) { isHovered = hovering }
            }
            .help(Text(verbatim: "buymeacoffee.com/patrickjakobsen"))
            .accessibilityHint("Opens Buy Me a Coffee in your browser.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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

// MARK: - Low Power Mode helper

/// Whether the panel's Low Power Mode switch works without a password, and a button to set that up.
private struct LowPowerModeHelperRow: View {
    let lowPowerMode: LowPowerMode

    var body: some View {
        LabeledContent {
            switch lowPowerMode.helperState {
            case .enabled:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(InlineIconLabelStyle(color: .green))
            case .requiresApproval:
                Button("Allow…") { SMAppService.openSystemSettingsLoginItems() }
            case .notRegistered, .unavailable:
                Button("Set Up…") { lowPowerMode.setUpHelper() }
            }
        } label: {
            SettingLabel("Low Power Mode Without a Password", symbol: "leaf.fill", color: .yellow) {
                Text("Lets the panel switch Low Power Mode right away. macOS asks you to allow it once, in Login Items.")
            }
        }
        .onAppear { lowPowerMode.refreshHelperState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            lowPowerMode.refreshHelperState()
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

// MARK: - History

/// Keeping a history on or off, and clearing it.
private struct HistoryRows: View {
    let model: AppModel
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.recordsHistory) {
            SettingLabel("Battery History", symbol: "chart.xyaxis.line", color: .green) {
                Text(
                    "The battery level and the apps that used it over the last 24 hours, and a summary of the last two weeks. Apps are measured every few minutes while on battery, and the history stays on this Mac."
                )
            }
        }
        LabeledContent {
            Button("Clear…") { isConfirmingClear = true }
                .disabled(model.history.history.isEmpty)
        } label: {
            SettingLabel("Clear History", symbol: "trash.fill", color: .gray)
        }
        .confirmationDialog("Clear the battery history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { model.history.clear() }
        } message: {
            Text("The charts, the apps that used the most battery and what's usual for this Mac start again from now.")
        }
    }
}

// MARK: - Menu bar style

/// Three menu bars side by side, one per icon style, each with the text you chose; click one to choose it.
private struct MenuBarStylePicker: View {
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
        let item = MenuBarItem(snapshot: snapshot, settings: settings, style: style, watts: watts, drawsForDarkBar: wallpaper.isDark)
        let icon = item.icon.isEmpty ? nil : item.icon.image()
        HStack(spacing: 4) {
            if item.leadsWithIcon, let icon { image(icon) }
            if let text = item.text {
                Text(text)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(item.showsTextAsLow ? Color.red : Color.primary)
                    .contentTransition(.numericText())
            }
            if !item.leadsWithIcon, let icon { image(icon) }
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

    private func image(_ icon: NSImage) -> some View {
        Image(nsImage: icon)
            .renderingMode(icon.isTemplate ? .template : .original)
    }
}
