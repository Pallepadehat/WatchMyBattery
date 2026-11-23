import AppKit
import BatteryKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Rules: what to do by itself when the battery drops to a level, charges to one, or the charger is
/// connected or disconnected. Turn on Low Power Mode, quit apps, change the charge limit, run a shortcut.
struct RulesPane: View {
    let model: AppModel
    /// The rule open in the editor: a copy, saved on Done.
    @State private var editing: BatteryRule?
    @State private var isNew = false

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                if settings.rules.isEmpty {
                    EmptyRules { suggestion in
                        settings.rules.append(BatteryRule(trigger: suggestion.trigger, actions: suggestion.actions))
                    }
                } else {
                    ForEach($settings.rules) { $rule in
                        RuleRow(rule: $rule, runner: model.rules) {
                            isNew = false
                            editing = rule
                        } delete: {
                            settings.rules.removeAll { $0.id == rule.id }
                        }
                    }
                }
            } header: {
                Text("Rules")
            } footer: {
                HStack {
                    Text("Rules run by themselves, on this Mac, while WatchMyBattery is open.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Rule…") {
                        isNew = true
                        editing = BatteryRule(trigger: .dropsTo(20), actions: [.lowPowerMode(true)])
                    }
                }
            }

            if usesLowPowerMode, model.lowPowerMode.helperState != .enabled, model.lowPowerMode.isSupported {
                Section {
                    HelperNote(lowPowerMode: model.lowPowerMode)
                }
            }

            Section {
                ShortcutsTips()
            } header: {
                Text("Shortcuts")
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: isNew, model: model) { saved in
                if let index = settings.rules.firstIndex(where: { $0.id == saved.id }) {
                    settings.rules[index] = saved
                } else {
                    settings.rules.append(saved)
                }
                editing = nil
            } delete: {
                settings.rules.removeAll { $0.id == rule.id }
                editing = nil
            } cancel: {
                editing = nil
            }
        }
        .task { model.lowPowerMode.refreshHelperState() }
    }

    private var usesLowPowerMode: Bool {
        model.settings.rules.contains { rule in
            rule.isEnabled && rule.actions.contains { if case .lowPowerMode = $0 { true } else { false } }
        }
    }
}

// MARK: - The list

/// One rule: its trigger, what it does, when it last ran, and a switch.
private struct RuleRow: View {
    @Binding var rule: BatteryRule
    let runner: RuleRunner
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SettingIcon(symbol: RuleText.triggerSymbol(rule.trigger), color: color, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(RuleText.trigger(rule.trigger))
                Text(rule.actions.isEmpty ? String(localized: "Does nothing yet") : rule.actions.map(RuleText.action).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let problem = runner.problems[rule.id] {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(InlineIconLabelStyle(color: .orange))
                        .font(.caption)
                } else if let ran = runner.lastRun[rule.id] {
                    Text("Ran at \(ran.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button("Edit…", action: edit)
                .controlSize(.small)
            Toggle("On", isOn: $rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .opacity(rule.isEnabled ? 1 : 0.6)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Run Now") { runner.run(rule) }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Run Now") { runner.run(rule) }
    }

    private var color: Color {
        switch rule.trigger {
        case .dropsTo: .orange
        case .chargesTo, .pluggedIn: Color(red: 0.2, green: 0.74, blue: 0.35)
        case .unplugged: .gray
        }
    }
}

/// No rules yet: what they're for, and two to start with.
private struct EmptyRules: View {
    let add: (BatteryRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingIcon(symbol: "wand.and.stars", color: RulesPane.color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let the battery look after itself")
                        .font(.headline)
                    Text(
                        "When the battery drops to a level, charges to one, or the charger comes and goes: turn on Low Power Mode, quit apps, change the charge limit or run a shortcut."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            HStack {
                ForEach(BatteryRule.suggestions, id: \.trigger) { suggestion in
                    Button {
                        add(suggestion)
                    } label: {
                        Label(Self.title(suggestion), systemImage: "plus")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private static func title(_ rule: BatteryRule) -> String {
        switch rule.trigger {
        case .dropsTo(let level): String(localized: "Low Power Mode at \(RuleText.percent(level))")
        case .pluggedIn: String(localized: "Low Power Mode off when plugged in")
        default: RuleText.trigger(rule.trigger)
        }
    }
}

/// Switching Low Power Mode without a password needs the helper.
private struct HelperNote: View {
    let lowPowerMode: LowPowerMode

    var body: some View {
        LabeledContent {
            Button(lowPowerMode.helperState == .requiresApproval ? "Open Login Items…" : "Allow…") { lowPowerMode.setUpHelper() }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow WatchMyBattery to switch Low Power Mode")
                    Text("Otherwise macOS asks for your password each time a rule switches it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
            }
            .labelStyle(InlineIconLabelStyle(color: .orange))
        }
    }
}

/// Where WatchMyBattery shows up in Shortcuts.
private struct ShortcutsTips: View {
    var body: some View {
        LabeledContent {
            Button("Open Shortcuts") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            SettingLabel("Run a Shortcut From a Rule", symbol: "square.2.layers.3d.top.filled", color: .pink) {
                Text(
                    "A rule can run any shortcut, by name. WatchMyBattery's own actions (the battery level, the time left, the forecast, Low Power Mode) are in Shortcuts too."
                )
            }
        }
    }
}

extension RulesPane {
    static let color = Color(red: 1, green: 0.42, blue: 0.2)
}

// MARK: - The editor

/// A rule, open for changing: when it runs, and what it does.
private struct RuleEditor: View {
    @State var rule: BatteryRule
    let isNew: Bool
    let model: AppModel
    let save: (BatteryRule) -> Void
    let delete: () -> Void
    let cancel: () -> Void

    init(
        rule: BatteryRule, isNew: Bool, model: AppModel, save: @escaping (BatteryRule) -> Void, delete: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        _rule = State(initialValue: rule)
        self.isNew = isNew
        self.model = model
        self.save = save
        self.delete = delete
        self.cancel = cancel
    }

    /// The four kinds of trigger, at a level for the ones that have one.
    private static let kinds: [BatteryRule.Trigger] = [.dropsTo(20), .chargesTo(80), .pluggedIn, .unplugged]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("When", selection: kindBinding) {
                        ForEach(Self.kinds, id: \.self) { kind in
                            Label(RuleText.triggerKind(kind), systemImage: RuleText.triggerSymbol(kind)).tag(kind)
                        }
                    }
                    if let level = rule.trigger.level {
                        Picker("Level", selection: Binding(get: { level }, set: { rule.trigger = rule.trigger.with(level: $0) })) {
                            ForEach(BatteryRule.levelChoices, id: \.self) { level in
                                Text(RuleText.percent(level)).tag(level)
                            }
                        }
                    }
                } header: {
                    Text("When")
                }

                Section {
                    if rule.actions.isEmpty {
                        Text("Add something for the rule to do.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rule.actions.indices, id: \.self) { index in
                        ActionRow(action: action(at: index), model: model) {
                            guard rule.actions.indices.contains(index) else { return }
                            rule.actions.remove(at: index)
                        }
                    }
                } header: {
                    HStack {
                        Text("Do")
                        Spacer()
                        addMenu
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button("Delete Rule", role: .destructive, action: delete)
                }
                Button("Run Now") { model.rules.run(rule) }
                    .disabled(rule.actions.isEmpty)
                    .help("Runs what it does now, to try it.")
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Done") { save(rule) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.actions.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 460)
    }

    /// One action, by position. Safe for a moment after one's removed, when SwiftUI may still ask for the last index.
    private func action(at index: Int) -> Binding<BatteryRule.Action> {
        Binding(
            get: { rule.actions.indices.contains(index) ? rule.actions[index] : .notify },
            set: { if rule.actions.indices.contains(index) { rule.actions[index] = $0 } })
    }

    private var kindBinding: Binding<BatteryRule.Trigger> {
        Binding(
            get: { Self.kinds.first { Self.sameKind($0, rule.trigger) } ?? rule.trigger },
            set: { kind in
                guard !Self.sameKind(kind, rule.trigger) else { return }
                rule.trigger = kind
            })
    }

    private static func sameKind(_ a: BatteryRule.Trigger, _ b: BatteryRule.Trigger) -> Bool {
        switch (a, b) {
        case (.dropsTo, .dropsTo), (.chargesTo, .chargesTo), (.pluggedIn, .pluggedIn), (.unplugged, .unplugged): true
        default: false
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Turn On Low Power Mode") { rule.actions.append(.lowPowerMode(true)) }
                .disabled(!model.lowPowerMode.isSupported)
            Button("Turn Off Low Power Mode") { rule.actions.append(.lowPowerMode(false)) }
                .disabled(!model.lowPowerMode.isSupported)
            Button("Quit Apps") { rule.actions.append(.quitApps([])) }
            Button("Change the Charge Limit") { rule.actions.append(.chargeLimit(80)) }
                .disabled(!model.chargeLimit.isSupported)
            Button("Run a Shortcut") { rule.actions.append(.runShortcut("")) }
            Button("Send a Notification") { rule.actions.append(.notify) }
                .disabled(rule.actions.contains(.notify))
        } label: {
            Label("Add", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .textCase(nil)
    }
}

/// One thing a rule does, with what it needs: the apps to quit, the shortcut, the limit.
private struct ActionRow: View {
    @Binding var action: BatteryRule.Action
    let model: AppModel
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: RuleText.actionSymbol(action))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                switch action {
                case .lowPowerMode(let on):
                    Picker("Low Power Mode", selection: Binding(get: { on }, set: { action = .lowPowerMode($0) })) {
                        Text("Turn On").tag(true)
                        Text("Turn Off").tag(false)
                    }
                case .quitApps(let apps):
                    QuitAppsEditor(apps: Binding(get: { apps }, set: { action = .quitApps($0) }))
                case .runShortcut(let name):
                    ShortcutPicker(name: Binding(get: { name }, set: { action = .runShortcut($0) }), runner: model.rules)
                case .chargeLimit(let level):
                    Picker("Charge Limit", selection: Binding(get: { level }, set: { action = .chargeLimit($0) })) {
                        ForEach(chargeChoices, id: \.self) { level in
                            Text(level >= 100 ? String(localized: "Off") : RuleText.percent(level)).tag(level)
                        }
                    }
                case .notify:
                    Text("Send a notification saying what the rule did")
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
            .accessibilityLabel("Remove")
        }
    }

    private var chargeChoices: [Int] {
        let choices = model.chargeLimit.choices
        return choices.isEmpty ? [80, 85, 90, 95, 100] : choices
    }
}

/// The apps a rule quits: chosen from what's running, or any app on the Mac.
private struct QuitAppsEditor: View {
    @Binding var apps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quit")
                Spacer()
                Menu("Add App") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.name) { add(app.bundleIdentifier) }
                    }
                    Divider()
                    Button("Choose…", action: choose)
                }
                .fixedSize()
            }
            if apps.isEmpty {
                Text("No apps yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(apps, id: \.self) { bundleIdentifier in
                HStack(spacing: 6) {
                    Image(nsImage: icon(for: bundleIdentifier))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(RuleText.appName(bundleIdentifier))
                    Spacer()
                    Button {
                        apps.removeAll { $0 == bundleIdentifier }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(RuleText.appName(bundleIdentifier))")
                }
                .font(.callout)
            }
        }
    }

    private var runningApps: [(name: String, bundleIdentifier: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .filter { !apps.contains($0.1) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    private func add(_ bundleIdentifier: String) {
        guard !apps.contains(bundleIdentifier) else { return }
        apps.append(bundleIdentifier)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleIdentifier = Bundle(url: url)?.bundleIdentifier { add(bundleIdentifier) }
        }
    }

    private func icon(for bundleIdentifier: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// A shortcut, picked from the Shortcuts app's list, or typed.
private struct ShortcutPicker: View {
    @Binding var name: String
    let runner: RuleRunner

    var body: some View {
        HStack {
            TextField("Shortcut", text: $name, prompt: Text("Name of the shortcut"))
            Menu {
                if runner.shortcuts.isEmpty {
                    Text(runner.isLoadingShortcuts ? "Loading…" : "No shortcuts found")
                }
                ForEach(runner.shortcuts, id: \.self) { shortcut in
                    Button(shortcut) { name = shortcut }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose from your shortcuts")
        }
        .onAppear { runner.loadShortcuts() }
    }
}
