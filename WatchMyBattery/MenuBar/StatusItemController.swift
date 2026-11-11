import AppKit
import BatteryKit
import Observation

/// The battery in the menu bar, and the panel it opens.
///
/// Left click opens the panel, like the built-in battery menu. Right click
/// (or Control-click) shows a small menu with Settings and Quit.
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var panel = BatteryPanelController(model: model, statusItem: statusItem)
    private var drawnIcon: BatteryIcon?
    private var drawnTitle: String?
    /// The icon as the battery and settings would have it, before any animation.
    private var currentIcon: BatteryIcon?
    private let chargingAnimator = ChargingAnimator()
    /// Nobody can see the menu bar: the displays are asleep, or another user is logged in.
    private var isOutOfSight = false
    private var workspaceTokens: [any NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        super.init()
        statusItem.autosaveName = "WatchMyBatteryStatusItem"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonPressed(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageRight
            button.imageHugsTitle = true
        }
        chargingAnimator.onFrame = { [weak self] glint in self?.drawIcon(glint: glint) }
        watchVisibility()
        observeChanges()
    }

    func showPanel() {
        panel.show()
    }

    func togglePanel() {
        panel.toggle()
    }

    @objc private func buttonPressed(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            panel.close()
            showMenu()
        } else {
            panel.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        if model.updater.canCheckForUpdates {
            menu.addItem(withTitle: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
                .target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit WatchMyBattery"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach it again, so the next left click goes to the panel.
        statusItem.menu = nil
    }

    @objc private func openSettings() { model.openSettings() }
    @objc private func checkForUpdates() {
        model.openSettings(.updates)
        model.updater.checkNow()
    }

    // MARK: - Keeping the icon current

    /// Redraws whenever the battery or the settings it depends on change.
    /// Observation tells us when something read here changed; the icon is
    /// compared with the one on screen, so it's redrawn only when it looks
    /// different.
    private func observeChanges() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeChanges() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let snapshot = model.battery.snapshot
        let icon = BatteryIcon(snapshot: snapshot, settings: model.settings)
        currentIcon = icon
        let animates = model.settings.showsChargingAnimation && snapshot.chargeState == .charging && !snapshot.isLowPowerModeOn
        updateAnimation(wanted: animates)
        if !chargingAnimator.isRunning { drawIcon(glint: nil) }

        let title = model.settings.percentageStyle == .beside ? snapshot.percentage.formatted(.percent) : ""
        if title != drawnTitle {
            button.attributedTitle = NSAttributedString(
                string: title.isEmpty ? "" : title + " ",
                attributes: [.font: NSFont.menuBarFont(ofSize: 0).monospacedDigits])
            drawnTitle = title
        }
    }
}

// MARK: - Charging animation

extension StatusItemController {
    /// Draws the current icon, with the glint where the animation has it. The
    /// icon is compared with the one on screen, so nothing is redrawn for nothing.
    fileprivate func drawIcon(glint: Double?) {
        guard let button = statusItem.button, var icon = currentIcon else { return }
        icon.chargeGlint = glint
        guard icon != drawnIcon else { return }
        button.image = icon.image()
        if icon.percentage != drawnIcon?.percentage || icon.chargeState != drawnIcon?.chargeState {
            button.setAccessibilityLabel(icon.accessibilityLabel)
        }
        drawnIcon = icon
    }

    /// Runs the animation only when it's wanted and someone could see it.
    fileprivate func updateAnimation(wanted: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if wanted && !reduceMotion && !isOutOfSight {
            chargingAnimator.start()
        } else {
            chargingAnimator.stop()
        }
    }

    /// Pauses the animation while the displays sleep or another user has the
    /// screen, and follows the Reduce Motion setting as it changes.
    fileprivate func watchVisibility() {
        let center = NSWorkspace.shared.notificationCenter
        let hidden: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let shown: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for (names, outOfSight) in [(hidden, true), (shown, false)] {
            for name in names {
                workspaceTokens.append(
                    center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.isOutOfSight = outOfSight
                            self?.updateButton()
                        }
                    })
            }
        }
        workspaceTokens.append(
            center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.updateButton() }
            })
    }
}

extension NSFont {
    var monospacedDigits: NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                ]
            ]
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
