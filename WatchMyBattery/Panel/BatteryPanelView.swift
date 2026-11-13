import BatteryKit
import SwiftUI

/// The panel that opens from the menu bar: the battery, the apps draining
/// it, and a few shortcuts. Laid out like the built-in Battery menu.
struct BatteryPanelView: View {
    let model: AppModel
    let close: () -> Void

    /// The app under the pointer (or being dragged): the time row previews quitting it.
    @State private var focusedApp: AppUsage?

    static let width: CGFloat = 320
    private static let inset: CGFloat = 16
    /// Every detail row is this tall, the height of the Low Power Mode switch, so they line up evenly.
    private static let rowHeight: CGFloat = 18
    private static let rowSpacing: CGFloat = 4

    private var snapshot: BatterySnapshot { model.battery.snapshot }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Self.inset)
                .padding(.top, 14)

            if snapshot.hasBattery {
                BatteryGauge(
                    snapshot: snapshot,
                    apps: model.usage.apps,
                    estimates: model.estimates,
                    centerLabel: model.settings.centerLabel,
                    usesColor: model.settings.usesColor,
                    animatesCharging: model.settings.showsChargingAnimation && model.isPanelOpen,
                    focusedApp: $focusedApp,
                    quit: { quit($0, asking: model.settings.confirmsQuit) },
                    confirmQuit: { quit($0, asking: true) },
                    exclude: { app in withAnimation(.snappy) { model.exclude(app) } },
                    systemWatts: model.settings.showsSystemSlice ? model.usage.systemSliceWatts : nil,
                    inspectedApp: model.usage.inspectedApp,
                    inspect: { app in
                        withAnimation(.snappy(duration: 0.3)) {
                            model.usage.inspectedApp = model.usage.inspectedApp == app.id ? nil : app.id
                        }
                    }
                )
                .padding(.horizontal, Self.inset)
                .padding(.top, 14)

                if let app = inspectedApp {
                    AppDetailCard(
                        app: app, processes: model.usage.inspectedProcesses,
                        quit: { quit(app, asking: model.settings.confirmsQuit) },
                        forceQuit: { withAnimation(.snappy) { model.usage.forceQuit(app.id) } },
                        close: { withAnimation(.snappy(duration: 0.3)) { model.usage.inspectedApp = nil } }
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // The details, one rhythm for all of them: a label on the left, its value on the right.
                VStack(spacing: Self.rowSpacing) {
                    if ChargeProgressRow.applies(to: snapshot) {
                        ChargeProgressRow(
                            snapshot: snapshot, usesColor: model.settings.usesColor,
                            animates: model.settings.showsChargingAnimation && model.isPanelOpen && !snapshot.isLowPowerModeOn && !reduceMotion
                        )
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if TimeRow.applies(to: snapshot) {
                        TimeRow(snapshot: snapshot, estimates: model.estimates, focusedApp: focusedApp)
                            .frame(minHeight: Self.rowHeight)
                    }
                    if let health = model.battery.health, !health.isEmpty {
                        HealthRow(health: health)
                            .frame(minHeight: Self.rowHeight)
                            .transition(.opacity)
                    }
                    if model.settings.showsChargeLimit, model.chargeLimit.isSupported {
                        ChargeLimitRow(chargeLimit: model.chargeLimit)
                            .frame(minHeight: Self.rowHeight)
                            .transition(.opacity)
                    }
                    if model.settings.showsBatteryReadings {
                        BatteryReadingsRows(
                            battery: model.battery, isVisible: model.isPanelOpen, usesColor: model.settings.usesColor, rowHeight: Self.rowHeight)
                    }
                    if model.lowPowerMode.isSupported {
                        LowPowerModeRow(isOn: snapshot.isLowPowerModeOn, isChanging: model.lowPowerMode.isChanging) { on in
                            setLowPowerMode(on)
                        }
                        .frame(minHeight: Self.rowHeight)
                    }
                }
                .padding(.horizontal, Self.inset)
                .padding(.top, 6)

                if model.lowPowerMode.suggests(for: snapshot) {
                    LowPowerSuggestion(
                        turnOn: { setLowPowerMode(true) },
                        dismiss: { withAnimation(.snappy) { model.lowPowerMode.isSuggestionDismissed = true } }
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if model.settings.showsInsights, InsightCards.hasAny(model.insights) {
                    InsightCards(
                        insights: model.insights, snapshot: snapshot,
                        turnOnLowPowerMode: model.lowPowerMode.isSupported ? { setLowPowerMode(true) } : nil
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let refusal = model.usage.refusal {
                    RefusalNotice(
                        refusal: refusal,
                        show: {
                            close()
                            model.usage.showRefusedApp()
                        },
                        forceQuit: { withAnimation(.snappy) { model.usage.forceQuit(refusal.id) } },
                        dismiss: { withAnimation(.snappy) { model.usage.dismissRefusal() } }
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .opacity))
                }

                accessoriesSection

                if model.settings.showsSleep, SleepSection.applies(to: model.sleep) {
                    Divider()
                        .padding(.horizontal, Self.inset)
                        .padding(.top, 10)
                    SleepSection(sleep: model.sleep, usesColor: model.settings.usesColor, rowHeight: Self.rowHeight)
                        .padding(.horizontal, Self.inset)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                if model.settings.recordsHistory {
                    @Bindable var settings = model.settings
                    Divider()
                        .padding(.horizontal, Self.inset)
                        .padding(.top, 10)
                    HistorySection(
                        recorder: model.history, snapshot: snapshot, usesColor: model.settings.usesColor, isVisible: model.isPanelOpen,
                        isExpanded: $settings.showsHistory, range: $settings.historyRange
                    )
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 8)
                }
            } else {
                Text("This Mac doesn't have a battery.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 12)
                accessoriesSection
            }

            if let version = model.updater.availableVersion {
                UpdateBanner(version: version) {
                    close()
                    model.updater.installUpdate()
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            if model.showsReplaceTip {
                ReplaceTip(
                    open: {
                        close()
                        model.openControlCenterSettings()
                    },
                    dismiss: {
                        withAnimation(.snappy) { model.settings.showsReplaceTip = false }
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .padding(.horizontal, Self.inset)
                .padding(.top, 10)
                .padding(.bottom, 5)

            VStack(spacing: 0) {
                MenuRow("Battery Settings…") {
                    close()
                    model.openBatterySettings()
                }
                MenuRow("WatchMyBattery Settings…") {
                    close()
                    model.openSettings()
                }
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.smooth(duration: 0.45), value: model.usage.apps.map(\.id))
        .animation(.smooth(duration: 0.6), value: snapshot)
        .animation(.snappy(duration: 0.3), value: model.usage.refusal)
        .animation(.snappy(duration: 0.3), value: model.lowPowerMode.suggests(for: snapshot))
        .animation(.snappy(duration: 0.3), value: InsightCards.hasAny(model.insights))
        .animation(.snappy(duration: 0.35), value: model.accessories.accessories.map(\.id))
        .animation(.snappy(duration: 0.3), value: model.usage.inspectedApp)
        .animation(.snappy(duration: 0.3), value: model.chargeLimit.isSupported)
    }

    /// The app whose slice was clicked, while it still has one.
    private var inspectedApp: AppUsage? {
        guard let pid = model.usage.inspectedApp else { return nil }
        return model.usage.apps.first { $0.id == pid }
    }

    /// Connected accessories with a battery, when there are any.
    @ViewBuilder private var accessoriesSection: some View {
        let accessories = model.accessories.accessories
        if model.settings.showsAccessories, !accessories.isEmpty {
            Divider()
                .padding(.horizontal, Self.inset)
                .padding(.top, 10)
            AccessoriesSection(accessories: accessories, monitor: model.accessories)
                .padding(.horizontal, Self.inset)
                .padding(.top, 8)
                .transition(.opacity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery")
                    .font(.system(size: 13, weight: .bold))
                if LaunchOptions.isIsolated {
                    // An end-to-end check's copy, next to the real app: say so, so nobody mistakes its blank settings.
                    Text(verbatim: "Test copy")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: .capsule)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if snapshot.hasBattery {
                    Text(snapshot.level, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: snapshot.level))
                }
            }
            // Like the system's Battery menu, the state goes with the power source ("Fully Charged"), so the rows
            // below only hold values. Low Power Mode has its own switch, so the header doesn't repeat it.
            Text(powerSourceDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var powerSourceDescription: LocalizedStringKey {
        switch (snapshot.powerSource, snapshot.chargeState) {
        case (.battery, _): "Power Source: Battery"
        case (.powerAdapter, .charged): "Power Source: Power Adapter · Fully Charged"
        // Held at its target on purpose: the charge bar says so, so "Not Charging" would only alarm.
        case (.powerAdapter, .notCharging) where snapshot.hasChargeLimit && snapshot.isAtTarget: "Power Source: Power Adapter"
        case (.powerAdapter, .notCharging): "Power Source: Power Adapter · Not Charging"
        case (.powerAdapter, _): "Power Source: Power Adapter"
        }
    }

    /// With the helper allowed, the switch just flips. Otherwise a password prompt or System Settings
    /// is about to take focus, so the panel steps aside.
    private func setLowPowerMode(_ on: Bool) {
        model.lowPowerMode.refreshHelperState()
        if model.lowPowerMode.helperState != .enabled { close() }
        model.setLowPowerMode(on)
    }

    /// Quits an app dragged out of the panel (or deleted with the keyboard), asking first when `asking`.
    private func quit(_ app: AppUsage, asking: Bool) {
        focusedApp = nil
        guard asking else {
            model.usage.quit(app)
            return
        }
        close()
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit \(app.name)?")
        alert.informativeText = String(localized: "\(app.name) will close. If it has unsaved changes, it will ask what to do with them.")
        alert.icon = app.icon
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { model.settings.confirmsQuit = false }
        if response == .alertFirstButtonReturn { model.usage.quit(app) }
    }
}

/// "Time left 4:50 +1:10": the estimate, and what quitting the focused app would add.
private struct TimeRow: View {
    let snapshot: BatterySnapshot
    let estimates: Estimates
    let focusedApp: AppUsage?

    /// Only on battery and while charging; when it's full or holding its charge, the header says so instead.
    static func applies(to snapshot: BatterySnapshot) -> Bool {
        snapshot.chargeState == .discharging || snapshot.chargeState == .charging
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let gained, gained >= 60 {
                Text(TimeFormat.gain(gained))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
        }
        .font(.system(size: 12))
        .animation(.snappy(duration: 0.25), value: focusedApp?.id)
        .animation(.snappy(duration: 0.25), value: snapshot)
    }

    private var gained: TimeInterval? {
        focusedApp.map { estimates.timeGained(byQuitting: $0.watts) }
    }

    private var title: LocalizedStringKey {
        if let focusedApp, gained ?? 0 >= 60 { return "Without \(focusedApp.name)" }
        guard snapshot.chargeState == .charging else { return "Time left" }
        return snapshot.hasChargeLimit ? "Until \((Double(snapshot.chargeTarget) / 100).formatted(.percent.precision(.fractionLength(0))))" : "Until full"
    }

    private var value: String {
        snapshot.timeRemaining.map(TimeFormat.clock) ?? String(localized: "Calculating…")
    }
}

/// "Battery Health  Normal · 88% · 564 cycles", under the time.
private struct HealthRow: View {
    let health: BatteryHealth

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Battery Health")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            // Everything if it fits; otherwise the least important parts go first, the cycle count, then the capacity.
            ViewThatFits(in: .horizontal) {
                summary(details(includingCycles: true))
                summary(details(includingCycles: false))
                summary(nil)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .help(
            "Maximum capacity is how much charge the battery holds compared with when it was new. A charge cycle is using 100% of its capacity, in total, not necessarily all at once."
        )
        .accessibilityElement(children: .combine)
    }

    private func summary(_ details: String?) -> some View {
        HStack(spacing: 6) {
            if health.condition == .serviceRecommended {
                Label("Service Recommended", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                    .fontWeight(.medium)
            }
            if let details, !details.isEmpty {
                Text(details)
                    .monospacedDigit()
            }
        }
        .fixedSize()
    }

    private func details(includingCycles: Bool) -> String {
        var parts: [String] = []
        if health.condition == .normal { parts.append(String(localized: "Normal")) }
        if let capacity = health.maximumCapacity {
            parts.append(capacity.formatted(.percent.precision(.fractionLength(0))))
        }
        if includingCycles, let cycles = health.cycleCount {
            parts.append(String(localized: "\(cycles) cycles"))
        }
        return parts.joined(separator: " · ")
    }
}

/// "Low Power Mode" with a switch, like the one in System Settings.
private struct LowPowerModeRow: View {
    let isOn: Bool
    let isChanging: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Low Power Mode")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if isChanging {
                ProgressView()
                    .controlSize(.mini)
            }
            Toggle("Low Power Mode", isOn: Binding(get: { isOn }, set: { set($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isChanging)
        }
        .font(.system(size: 12))
        .help("Reduces energy use, so the battery lasts longer.")
    }
}

/// Running low: offer Low Power Mode, the way the iPhone does at 20%.
private struct LowPowerSuggestion: View {
    let turnOn: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 15))
                .foregroundStyle(.yellow)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Battery is low")
                    .font(.system(size: 12, weight: .semibold))
                Text("Low Power Mode makes it last longer, by reducing energy use.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn On Low Power Mode", action: turnOn)
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
            }
            Spacer(minLength: 0)
            DismissButton(action: dismiss)
        }
        .padding(10)
        .background(.yellow.opacity(0.16), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// An app that didn't quit when it was dragged out: say so, and offer to show it.
private struct RefusalNotice: View {
    let refusal: QuitRefusal
    let show: () -> Void
    let forceQuit: () -> Void
    let dismiss: () -> Void
    @State private var isConfirmingForceQuit = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: refusal.icon)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(refusal.name) didn't quit")
                    .font(.system(size: 12, weight: .semibold))
                Text("It may be asking what to do with unsaved changes, or have stopped responding.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Show \(refusal.name)", action: show)
                    if isConfirmingForceQuit {
                        Button("Force Quit, Losing Unsaved Changes", action: forceQuit)
                            .foregroundStyle(.red)
                            .transition(.opacity)
                    } else {
                        Button("Force Quit…") { withAnimation(.snappy(duration: 0.2)) { isConfirmingForceQuit = true } }
                            .help("Quits it straight away, without asking about unsaved changes.")
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
            }
            Spacer(minLength: 0)
            DismissButton(action: dismiss)
        }
        .padding(10)
        .background(.orange.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// The small round × that closes a notice.
struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(.quaternary, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}

/// A row that highlights under the pointer, like a menu item.
struct MenuRow: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .contentShape(.rect)
                // The menu highlight: the accent colour with white text, in light and dark alike.
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                        .opacity(isHovered ? 1 : 0)
                )
                .foregroundStyle(isHovered ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The background check found a new version.
private struct UpdateBanner: View {
    let version: String
    let install: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Update available").font(.system(size: 12, weight: .semibold))
                Text("Version \(version) is ready to install.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Install", action: install)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

/// Explains how to hide Apple's battery icon, so this one replaces it.
private struct ReplaceTip: View {
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Two batteries in your menu bar?")
                    .font(.system(size: 12, weight: .semibold))
                Text("Hide the built-in one: Control Center › Battery › Don't Show in Menu Bar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Control Center Settings", action: open)
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
            }
            Spacer(minLength: 0)
            DismissButton(action: dismiss)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
    }
}
