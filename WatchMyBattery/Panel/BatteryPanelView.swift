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

    private var snapshot: BatterySnapshot { model.battery.snapshot }

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
                    exclude: { app in withAnimation(.snappy) { model.exclude(app) } }
                )
                .padding(.horizontal, Self.inset)
                .padding(.top, 14)

                TimeRow(snapshot: snapshot, estimates: model.estimates, focusedApp: focusedApp)
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 8)

                if let health = model.battery.health, !health.isEmpty {
                    HealthRow(health: health)
                        .padding(.horizontal, Self.inset)
                        .padding(.top, 3)
                        .transition(.opacity)
                }

                if let refusal = model.usage.refusal {
                    RefusalNotice(
                        refusal: refusal,
                        show: {
                            close()
                            model.usage.showRefusedApp()
                        },
                        dismiss: { withAnimation(.snappy) { model.usage.dismissRefusal() } }
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .opacity))
                }
            } else {
                Text("This Mac doesn't have a battery.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 12)
            }

            if let version = model.updater.availableVersion {
                UpdateBanner(version: version) {
                    close()
                    model.updater.installUpdate()
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            if model.settings.showsReplaceTip {
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if snapshot.hasBattery {
                    Text(snapshot.level, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: snapshot.level))
                }
            }
            HStack(spacing: 6) {
                Text(powerSourceDescription)
                if snapshot.isLowPowerModeOn {
                    Text("Low Power Mode")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.yellow.opacity(0.25), in: .capsule)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }

    private var powerSourceDescription: LocalizedStringKey {
        snapshot.powerSource == .battery ? "Power Source: Battery" : "Power Source: Power Adapter"
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
        .font(.system(size: 13))
        .animation(.snappy(duration: 0.25), value: focusedApp?.id)
        .animation(.snappy(duration: 0.25), value: snapshot)
    }

    private var gained: TimeInterval? {
        focusedApp.map { estimates.timeGained(byQuitting: $0.watts) }
    }

    private var title: LocalizedStringKey {
        if let focusedApp, gained ?? 0 >= 60 { return "Without \(focusedApp.name)" }
        switch snapshot.chargeState {
        case .discharging: return "Time left"
        case .charging: return "Until full"
        case .charged: return "Fully charged"
        case .notCharging: return "Not charging"
        }
    }

    private var value: String {
        switch snapshot.chargeState {
        case .discharging, .charging:
            snapshot.timeRemaining.map(TimeFormat.clock) ?? String(localized: "Calculating…")
        case .charged, .notCharging:
            ""
        }
    }
}

/// "Battery Health  Normal · 88% · 564 cycles": quiet, under the time.
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
                    .foregroundStyle(.secondary)
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

/// An app that didn't quit when it was dragged out: say so, and offer to show it.
private struct RefusalNotice: View {
    let refusal: QuitRefusal
    let show: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: refusal.icon)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(refusal.name) didn't quit")
                    .font(.system(size: 12, weight: .semibold))
                Text("It may be asking what to do with unsaved changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show \(refusal.name)", action: show)
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
private struct DismissButton: View {
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
