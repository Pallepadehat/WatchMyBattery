import AppKit
import BatteryKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Charging

/// The charge limit, a one-off charge to full, and the "charged" notification.
struct ChargingPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let chargeLimit = model.chargeLimit
        Form {
            Section {
                if chargeLimit.isSupported {
                    ChargeLimitSlider(chargeLimit: chargeLimit, afterTopUp: settings.chargeLimitAfterTopUp)
                    if chargeLimit.isToppingUp {
                        LabeledContent {
                            Button("Restore Limit") { chargeLimit.cancelTopUp() }
                        } label: {
                            SettingLabel("Charging to 100% Once", symbol: "bolt.fill", color: .green) {
                                Text("Your \(Self.percent(settings.chargeLimitAfterTopUp)) limit comes back when you unplug.")
                            }
                        }
                    } else if chargeLimit.isLimited {
                        LabeledContent {
                            Button("Charge to 100%") { chargeLimit.chargeToFullOnce() }
                                .disabled(chargeLimit.isChanging)
                        } label: {
                            SettingLabel("Charge to Full Once", symbol: "bolt.fill", color: .green) {
                                Text("For a long day away from a charger. The limit comes back when you unplug.")
                            }
                        }
                    }
                    if let failure = chargeLimit.failure {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(InlineIconLabelStyle(color: .orange))
                            .font(.caption)
                    }
                } else {
                    SettingLabel("Charge Limit", symbol: "battery.75percent", color: .gray) {
                        Text("Needs a Mac with Apple silicon and macOS 26.4 or later.")
                    }
                }
            } header: {
                Text("Charge Limit")
            } footer: {
                Text("macOS holds the limit itself, so it stays on when WatchMyBattery isn't running. It's the same setting as in System Settings › Battery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy, value: chargeLimit.isLimited)
            .animation(.snappy, value: chargeLimit.isToppingUp)

            Section {
                ChargedNotificationRows(model: model)
            } header: {
                Text("Notification")
            }

            Section {
                Toggle(isOn: $settings.showsChargeLimit) {
                    SettingLabel("Show in the Panel", symbol: "menubar.rectangle", color: .gray) {
                        Text("Change the limit right from the menu bar.")
                    }
                }
                .disabled(!chargeLimit.isSupported)
                LabeledContent {
                    Button("Open…") { model.openBatterySettings() }
                } label: {
                    SettingLabel("Battery Settings", symbol: SettingIcon.battery, color: .green) {
                        Text("Optimized Battery Charging and more, in System Settings.")
                    }
                }
            }
        }
        .onAppear { chargeLimit.refresh() }
    }

    static func percent(_ level: Int) -> String {
        (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The charge limit as a stepped slider, like System Settings' own: from the lowest level macOS offers to 100%, which
/// is no limit. The change goes to macOS when the slider is let go, not on every step.
private struct ChargeLimitSlider: View {
    let chargeLimit: ChargeLimit
    let afterTopUp: Int

    /// Where the slider is while it's being dragged.
    @State private var draft: Double?
    @State private var isEditing = false
    /// When the last change was sent: the slider echoes values back as the limit catches up, and those aren't choices.
    @State private var lastCommit = Date.distantPast

    private var lower: Int { chargeLimit.choices.first ?? 80 }
    private var upper: Int { chargeLimit.choices.last ?? 100 }
    private var step: Int { chargeLimit.choices.count > 1 ? chargeLimit.choices[1] - chargeLimit.choices[0] : 5 }

    /// The limit shown: the one being dragged to, or during a one-off charge to full, the one coming back.
    private var shown: Int {
        if let draft { return Int(draft.rounded()) }
        return chargeLimit.isToppingUp && afterTopUp > 0 ? afterTopUp : chargeLimit.limit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                HStack(spacing: 6) {
                    if chargeLimit.isChanging {
                        ProgressView().controlSize(.small)
                    }
                    Text(shown >= ChargeLimitClient.Levels.noLimit ? String(localized: "Off") : ChargingPane.percent(shown))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown)))
                        .foregroundStyle(.secondary)
                }
            } label: {
                SettingLabel("Charge Limit", symbol: symbol, color: .green) {
                    Text(subtitle)
                }
            }

            HStack(spacing: 10) {
                Text(ChargingPane.percent(lower))
                Slider(value: binding, in: Double(lower)...Double(upper), step: Double(step)) {
                    Text("Charge Limit")
                } onEditingChanged: { editing in
                    isEditing = editing
                    if !editing { commit() }
                }
                .labelsHidden()
                Text(ChargingPane.percent(upper))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 34)
            .disabled(chargeLimit.isChanging)
        }
        .accessibilityElement(children: .contain)
    }

    private var binding: Binding<Double> {
        Binding(
            get: { Double(shown) },
            set: { value in
                if isEditing {
                    draft = value
                    return
                }
                // From the keyboard or VoiceOver there's no drag to wait for. Anything else outside a drag is the
                // slider echoing the old value while macOS takes the new one: never send that back.
                guard Int(value.rounded()) != shown, !chargeLimit.isChanging, Date.now.timeIntervalSince(lastCommit) > 1.5 else { return }
                draft = value
                commit()
            })
    }

    private func commit() {
        guard let draft else { return }
        self.draft = nil
        let level = chargeLimit.choices.min { abs(Double($0) - draft) < abs(Double($1) - draft) } ?? Int(draft)
        guard level != chargeLimit.limit || chargeLimit.isToppingUp else { return }
        lastCommit = .now
        chargeLimit.set(level)
    }

    private var symbol: String {
        switch shown {
        case ..<85: "battery.75percent"
        case ..<100: "battery.100percent"
        default: "battery.100percent.bolt"
        }
    }

    private var subtitle: String {
        if shown >= ChargeLimitClient.Levels.noLimit {
            return String(localized: "Charges all the way. A limit keeps the battery from sitting full, which wears it fastest.")
        }
        return String(localized: "Stops charging at \(ChargingPane.percent(shown)) while plugged in, so the battery lasts longer.")
    }
}

/// The "charged to" notification: on or off, and at which level.
struct ChargedNotificationRows: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.notifiesWhenCharged) {
            SettingLabel("When It's Charged", symbol: "bolt.badge.checkmark.fill", color: .green) {
                Text("A notification when the battery reaches a level, to unplug.")
            }
        }
        .onChange(of: settings.notifiesWhenCharged) { _, on in
            if on { Task { await model.notifier.requestAuthorization() } }
        }
        if settings.notifiesWhenCharged {
            Picker("Notify At", selection: $settings.chargedLevel) {
                ForEach(AppSettings.chargedLevelChoices, id: \.self) { level in
                    Text(ChargingPane.percent(level)).tag(level)
                }
            }
            .padding(.leading, 34)
            // A charge limit below it stops the battery first: the notification comes at the limit instead.
            if let limit = model.battery.chargeLimit, limit < settings.chargedLevel {
                Label("Your charge limit stops charging at \(ChargingPane.percent(limit)), so the notification comes then.", systemImage: "info.circle")
                    .labelStyle(InlineIconLabelStyle(color: .secondary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34)
            }
            NotificationsDeniedRow(notifier: model.notifier)
        }
    }
}

// MARK: - Sleep

/// Recent sleeps and how much each used, what's keeping the Mac awake now, and the sleep notification.
struct SleepPane: View {
    let model: AppModel
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var settings = model.settings
        let log = model.sleep.log
        Form {
            Section {
                if log.isEmpty {
                    Text("Nothing yet. Sleeps show here once your Mac has slept and woken with WatchMyBattery running.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.recent(since: .distantPast).prefix(14)) { session in
                        SleepHistoryRow(session: session)
                    }
                }
            } header: {
                Text("Recent Sleeps")
            } footer: {
                if let typical = log.typicalPerHour {
                    Text("Typically \(typical.formatted(.number.precision(.fractionLength(1))))% an hour asleep on battery. About 1% or less is normal.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if model.sleep.holders.isEmpty {
                    Label("Nothing is keeping your Mac awake.", systemImage: "checkmark.circle.fill")
                        .labelStyle(InlineIconLabelStyle(color: .green))
                } else {
                    ForEach(model.sleep.holders) { holder in
                        AwakeHolderRow(holder: holder)
                    }
                }
            } header: {
                Text("Keeping Your Mac Awake")
            } footer: {
                Text(
                    "Apps ask macOS not to sleep to finish a download, play something, or keep a call going. One that forgets to stop keeps the Mac awake with the lid closed, or long after you've walked away."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.showsSleep) {
                    SettingLabel("Sleep in the Panel", symbol: "moon.zzz.fill", color: .purple) {
                        Text("The last sleep, and what's keeping the Mac awake.")
                    }
                }
                SleepDrainNotificationRows(model: model)
                LabeledContent {
                    Button("Open…") { model.openBatterySettings() }
                } label: {
                    SettingLabel("Wake for Network Access", symbol: "wifi", color: .blue) {
                        Text("Often why a Mac uses battery asleep. Turn it off in System Settings › Battery › Options.")
                    }
                }
                LabeledContent {
                    Button("Clear…") { isConfirmingClear = true }
                        .disabled(log.isEmpty)
                } label: {
                    SettingLabel("Clear Sleeps", symbol: "trash.fill", color: .gray)
                }
                .confirmationDialog("Clear the sleeps?", isPresented: $isConfirmingClear) {
                    Button("Clear Sleeps", role: .destructive) { model.sleep.clear() }
                }
            }
        }
        .onAppear { model.sleep.panelDidOpen() }
        .onDisappear { if !model.isPanelOpen { model.sleep.panelDidClose() } }
    }
}

/// "Yesterday, 23:10 – 07:22  8h 12m · 6% used  0.7%/h"
private struct SleepHistoryRow: View {
    let session: SleepSession

    var body: some View {
        LabeledContent {
            if let used = session.used {
                HStack(spacing: 10) {
                    Text((Double(used) / 100).formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let rate = session.perHour {
                        Text(String(localized: "\(rate.formatted(.number.precision(.fractionLength(1))))%/h"))
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(color)
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                }
            } else {
                Text("Plugged in")
                    .foregroundStyle(.tertiary)
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.start.formatted(.relative(presentation: .named, unitsStyle: .wide)).capitalizedFirst)
                    Text(
                        "\(session.start.formatted(date: .omitted, time: .shortened)) – \(session.end.formatted(date: .omitted, time: .shortened)) · \(DurationText.short(session.duration))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
        }
    }

    private var color: Color {
        switch session.drain {
        case .heavy: .red
        case .elevated: .orange
        case .normal: .green
        case .unknown: .gray.opacity(0.5)
        }
    }
}

/// The notification after a sleep that used much more than it should.
struct SleepDrainNotificationRows: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Toggle(isOn: $settings.notifiesAboutSleepDrain) {
            SettingLabel("Heavy Drain While Asleep", symbol: "moon.haze.fill", color: .indigo) {
                Text("A notification on waking when the Mac used much more battery asleep than it should.")
            }
        }
        .onChange(of: settings.notifiesAboutSleepDrain) { _, on in
            if on { Task { await model.notifier.requestAuthorization() } }
        }
        if settings.notifiesAboutSleepDrain {
            NotificationsDeniedRow(notifier: model.notifier)
        }
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

// MARK: - History: how long, and exporting

/// How long the history is kept, and exporting it as CSV or JSON.
struct HistoryKeepRows: View {
    let model: AppModel
    @State private var exportFailure: String?

    var body: some View {
        Picker(selection: Binding(get: { model.settings.historyRetention }, set: { model.setHistoryRetention($0) })) {
            ForEach(HistoryRetention.allCases) { retention in
                Text(retention.title).tag(retention)
            }
        } label: {
            SettingLabel("Keep History For", symbol: "calendar", color: .red) {
                Text("Hourly summaries, a few kilobytes a day. Insights always look at the last two weeks.")
            }
        }
        .disabled(!model.settings.recordsHistory)

        LabeledContent {
            Menu("Export…") {
                Button("Spreadsheet (CSV)…") { export(.csv) }
                Button("JSON…") { export(.json) }
            }
            .fixedSize()
            .disabled(model.history.history.isEmpty && model.history.profile.isEmpty)
        } label: {
            SettingLabel("Export History", symbol: "square.and.arrow.up.fill", color: .blue) {
                if let exportFailure {
                    Label(exportFailure, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(InlineIconLabelStyle(color: .orange))
                } else {
                    Text("CSV has a row for every hour. JSON has everything, sleeps included.")
                }
            }
        }
    }

    private func export(_ format: HistoryExport.Format) {
        exportFailure = nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = HistoryExport.suggestedFileName(format)
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.history.export(format, sleeps: model.sleep.log).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportFailure = error.localizedDescription
        }
    }
}

extension String {
    /// "yesterday" → "Yesterday", for a relative date at the start of a line.
    fileprivate var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
