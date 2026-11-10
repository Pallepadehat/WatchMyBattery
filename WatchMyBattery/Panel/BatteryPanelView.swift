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
                    focusedApp: $focusedApp,
                    quit: quit
                )
                .padding(.horizontal, Self.inset)
                .padding(.top, 14)

                TimeRow(snapshot: snapshot, estimates: model.estimates, focusedApp: focusedApp)
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 8)
            } else {
                Text("This Mac doesn't have a battery.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, 12)
            }

            if let version = model.updater.availableVersion {
                UpdateBanner(version: version) {
                    close()
                    model.updater.checkNow()
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

    /// Quits an app dragged out of the panel, asking first if the user wants that.
    private func quit(_ app: AppUsage) {
        focusedApp = nil
        guard model.settings.confirmsQuit else {
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
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
                )
                .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
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
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(.quaternary, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
    }
}
