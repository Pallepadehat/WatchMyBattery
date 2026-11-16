import BatteryKit
import SwiftUI

/// The welcome tour: what WatchMyBattery does, then a step for each set of choices, the menu bar, how it moves, the
/// panel, notifications, and the finishing touches, each applied the moment it's made, so closing early keeps them.
/// It opens with ``OnboardingIntro``'s animation.
struct OnboardingView: View {
    let model: AppModel
    /// Done: close the tour, and open the panel, so it's clear where WatchMyBattery lives.
    let finish: () -> Void
    /// Closed early, with the ×.
    let close: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, menuBar, motion, panel, notifications, finishing
    }

    @State private var step: Step
    /// Starts settled, without the opening: for the previews.
    private let skipsOpening: Bool

    init(model: AppModel, startingAt step: Step = .welcome, skipsOpening: Bool = false, finish: @escaping () -> Void, close: @escaping () -> Void) {
        self.model = model
        _step = State(initialValue: step)
        self.skipsOpening = skipsOpening
        self.finish = finish
        self.close = close
    }

    /// Which way the last step went, so the next one slides in from the right side.
    @State private var isGoingBack = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tint = Color(red: 0.2, green: 0.78, blue: 0.35)

    var body: some View {
        OnboardingIntro(tint: Self.tint, compactLogo: step != .welcome, skipsOpening: skipsOpening) { isSettled in
            Image(systemName: "battery.100percent.bolt")
                .font(.system(size: 210, weight: .regular))
                .foregroundStyle(.white)
                .blendMode(.softLight)
                .scaleEffect(isSettled ? (step == .welcome ? 0.42 : 0.19) : 1)
        } content: { _ in
            VStack(spacing: 16) {
                header
                    .id(step)
                    .transition(slide)
                ZStack(alignment: .top) {
                    stepContent
                        .id(step)
                        .transition(slide)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                footer
                progressDots
            }
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } onClose: {
            close()
        }
    }

    /// Steps slide in the way the tour goes, or just cross-fade with Reduce Motion.
    private var slide: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: isGoingBack ? .leading : .trailing).combined(with: .opacity),
            removal: .move(edge: isGoingBack ? .trailing : .leading).combined(with: .opacity))
    }

    private func go(to next: Step) {
        isGoingBack = next.rawValue < step.rawValue
        withAnimation(.snappy(duration: 0.35)) { step = next }
    }

    // MARK: - Header and footer

    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(step == .welcome ? .largeTitle.weight(.bold) : .title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }

    private var title: LocalizedStringKey {
        switch step {
        case .welcome: "Welcome to WatchMyBattery"
        case .menuBar: "Your Menu Bar"
        case .motion: "How It Moves"
        case .panel: "What the Panel Shows"
        case .notifications: "Notifications"
        case .finishing: "Finishing Touches"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch step {
        case .welcome: "See what's draining your battery, right from the menu bar."
        case .menuBar: "Pick how the battery looks up there, and what goes beside it."
        case .motion: "The battery can move while it charges, and while it's held at your limit."
        case .panel: "Choose what the panel shows when you click the battery. The apps draining it are always there."
        case .notifications: "A nudge at the right moment. All of them are off until you turn them on."
        case .finishing: "Open the panel from anywhere, and keep WatchMyBattery running."
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") { go(to: Step(rawValue: step.rawValue - 1) ?? .welcome) }
                    .controlSize(.large)
                    .keyboardShortcut("[", modifiers: .command)
                    .transition(.opacity)
            }
            Button {
                if let next = Step(rawValue: step.rawValue + 1) { go(to: next) } else { finish() }
            } label: {
                Text(step == .welcome ? "Get Started" : step == .finishing ? "Done" : "Continue")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.tint)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .animation(.snappy(duration: 0.25), value: step)
    }

    /// Where in the tour it is.
    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { each in
                Capsule()
                    .fill(each == step ? AnyShapeStyle(Self.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: each == step ? 14 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: step)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))
    }

    // MARK: - The steps

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .menuBar: MenuBarStep(model: model)
        case .motion: MotionStep(settings: model.settings)
        case .panel: PanelStep(model: model)
        case .notifications: NotificationsStep(model: model)
        case .finishing: FinishingStep(model: model)
        }
    }
}

// MARK: - Shared pieces

/// A step's card: a rounded group, like a Settings section.
private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 32)
    }
}

/// A row with an icon, a title and a line about it, and a control at the end.
private struct OnboardingRow<Control: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    var color: Color = OnboardingView.tint
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingIcon(symbol: symbol, color: color, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// A switch in an ``OnboardingRow``.
private struct OnboardingToggle: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    var color: Color = OnboardingView.tint
    @Binding var isOn: Bool

    var body: some View {
        OnboardingRow(title: title, detail: detail, symbol: symbol, color: color) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(OnboardingView.tint)
        }
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    var body: some View {
        OnboardingCard {
            Feature(
                symbol: "chart.bar.doc.horizontal.fill", title: "The apps, in the battery",
                detail: "Each app draining it gets a slice, with the time it costs you.")
            Feature(
                symbol: "hand.draw.fill", title: "Drag one out to quit it",
                detail: "Pull a slice out of the panel and it's gone, like an icon from the Dock.")
            Feature(
                symbol: "clock.arrow.circlepath", title: "History and insights",
                detail: "Ten days of battery, and a heads-up when something's unusual.")
            Feature(
                symbol: "airpodspro", title: "Your accessories too",
                detail: "AirPods, Magic devices, your iPhone and iPad, all in one place.")
        }
    }

    private struct Feature: View {
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingView.tint)
                    .frame(width: 26)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - The menu bar

private struct MenuBarStep: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        OnboardingCard {
            // How it looks up there now, on a slice of menu bar.
            MenuBarItemView(item: MenuBarItem(snapshot: model.battery.snapshot, settings: settings, watts: model.powerDraw.watts))
                .scaleEffect(1.6)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(.background.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
                .animation(.snappy, value: settings.menuBarIconStyle)

            Picker("Style", selection: $settings.menuBarIconStyle.animation(.snappy)) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            OnboardingRow(title: "Beside It", detail: "Or nothing, for just the icon.", symbol: "textformat") {
                Picker("Beside It", selection: Binding(get: { settings.effectiveMenuBarLabel }, set: { settings.menuBarLabel = $0 })) {
                    ForEach(MenuBarLabel.allCases) { label in
                        if label != .none || settings.menuBarIconStyle != .textOnly {
                            Text(label.title).tag(label)
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            OnboardingToggle(
                title: "Colorful States", detail: "Green charging, yellow in Low Power Mode, red when low.", symbol: "paintpalette.fill",
                color: .orange, isOn: $settings.usesColor)
        }
    }
}

// MARK: - How it moves

private struct MotionStep: View {
    @Bindable var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingCard {
            OnboardingToggle(
                title: "Charging Animation", detail: "In the menu bar and the panel.", symbol: "bolt.fill",
                isOn: $settings.showsChargingAnimation.animation(.snappy))
            if settings.showsChargingAnimation {
                Divider()
                if reduceMotion {
                    Label("Reduce Motion is on, so the battery stays still.", systemImage: "figure.walk.motion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                MotionChoice(
                    title: "While Charging", snapshot: MotionPreview.Sample.charging, selection: $settings.chargingMotion, usesColor: settings.usesColor
                ) {
                    MenuBarMotion(snapshot: MotionPreview.Sample.charging, charging: $0, trickle: .slowPulse, holding: .breathing)
                }
                MotionChoice(
                    title: "Last Few Percent", snapshot: MotionPreview.Sample.trickling, selection: $settings.trickleMotion, usesColor: settings.usesColor
                ) {
                    MenuBarMotion(snapshot: MotionPreview.Sample.trickling, charging: .flow, trickle: $0, holding: .breathing)
                }
                MotionChoice(
                    title: "Holding the Charge", snapshot: MotionPreview.Sample.holding, selection: $settings.holdingMotion, usesColor: settings.usesColor
                ) {
                    MenuBarMotion(snapshot: MotionPreview.Sample.holding, charging: .flow, trickle: .slowPulse, holding: $0)
                }
            }
        }
    }

    /// One state: its battery playing the chosen style, and a segmented control to choose another.
    private struct MotionChoice<Style: MotionStyle>: View {
        let title: LocalizedStringKey
        let snapshot: BatterySnapshot
        @Binding var selection: Style
        let usesColor: Bool
        let motion: (Style) -> MenuBarMotion?

        var body: some View {
            HStack(spacing: 14) {
                MotionPreview(snapshot: snapshot, motion: motion(selection), usesColor: usesColor, scale: 2.2)
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker(title, selection: $selection) {
                        ForEach(Style.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - The panel

private struct PanelStep: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        OnboardingCard {
            OnboardingToggle(
                title: "Battery History", detail: "24 hours and 10 days, and the apps that used the most.", symbol: "chart.bar.fill",
                color: .blue, isOn: $settings.recordsHistory)
            OnboardingToggle(
                title: "Insights", detail: "When it drains faster than usual, or a new app uses a lot.", symbol: "lightbulb.fill", color: .yellow,
                isOn: $settings.showsInsights)
            OnboardingToggle(
                title: "Accessories", detail: "AirPods, Magic devices, your iPhone and iPad.", symbol: "airpodspro", color: .cyan,
                isOn: $settings.showsAccessories)
            OnboardingToggle(
                title: "Sleep", detail: "What the last sleep used, and what's keeping the Mac awake.", symbol: "moon.zzz.fill",
                color: .purple, isOn: $settings.showsSleep)
            OnboardingToggle(
                title: "Battery Readings", detail: "Its temperature, voltage and current.", symbol: "thermometer.medium", color: .orange,
                isOn: $settings.showsBatteryReadings)
            if model.chargeLimit.isSupported {
                OnboardingToggle(
                    title: "Charge Limit", detail: "Hold the battery short of full, from the panel, so it lasts longer.", symbol: "shield.lefthalf.filled",
                    color: Color(red: 0.2, green: 0.74, blue: 0.62), isOn: $settings.showsChargeLimit)
            }
        }
    }
}

// MARK: - Notifications

private struct NotificationsStep: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        OnboardingCard {
            OnboardingToggle(
                title: "Low Battery", detail: "When it runs low, naming the app using the most.", symbol: SettingIcon.lowBattery, color: .red,
                isOn: $settings.notifiesWhenLow
            )
            .requestsNotifications(whenOn: settings.notifiesWhenLow, from: model.notifier)
            OnboardingToggle(
                title: "Charged", detail: "At \(Self.percent(settings.chargedLevel)), so you can unplug.", symbol: "powerplug.fill",
                isOn: $settings.notifiesWhenCharged
            )
            .requestsNotifications(whenOn: settings.notifiesWhenCharged, from: model.notifier)
            OnboardingToggle(
                title: "Accessories Running Low", detail: "AirPods, a Magic Mouse or keyboard, at \(Self.percent(settings.accessoryLowBatteryLevel)).",
                symbol: "airpodspro", color: .cyan, isOn: $settings.notifiesWhenAccessoryLow
            )
            .requestsNotifications(whenOn: settings.notifiesWhenAccessoryLow, from: model.notifier)
            OnboardingToggle(
                title: "Apps Using a Lot", detail: "When one keeps draining it, with a button to quit it.", symbol: "flame.fill", color: .orange,
                isOn: $settings.notifiesAboutRunawayApps
            )
            .requestsNotifications(whenOn: settings.notifiesAboutRunawayApps, from: model.notifier)
            if model.notifier.isDenied {
                Label("Notifications are off for WatchMyBattery in System Settings.", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(InlineIconLabelStyle(color: .orange))
                    .font(.caption)
            }
        }
        .task { await model.notifier.refreshAuthorization() }
    }

    private static func percent(_ level: Int) -> String {
        (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Finishing touches

private struct FinishingStep: View {
    let model: AppModel

    var body: some View {
        OnboardingCard {
            OnboardingRow(title: "Keyboard Shortcut", detail: "Opens and closes the panel from any app.", symbol: "command", color: .gray) {
                ShortcutRecorder(model: model)
            }
            OnboardingToggle(
                title: "Open at Login", detail: "Keep the battery in your menu bar.", symbol: "power", color: .gray,
                isOn: Binding(get: { model.launchAtLogin.isEnabled }, set: { model.launchAtLogin.setEnabled($0) }))
            if model.isBuiltInBatteryShown != false {
                OnboardingRow(
                    title: "Hide macOS's Battery", detail: "So there's one battery up there. Control Center › Battery.",
                    symbol: "rectangle.topthird.inset.filled", color: .gray
                ) {
                    Button("Open…") { model.openControlCenterSettings() }
                }
            }
        }
        .onAppear {
            model.launchAtLogin.refresh()
            model.refreshBuiltInBatteryShown()
        }
    }
}
