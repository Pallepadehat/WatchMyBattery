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
        observeChanges()
    }

    func showPanel() {
        panel.show()
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
    @objc private func checkForUpdates() { model.updater.checkNow() }

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
        if icon != drawnIcon {
            button.image = icon.image()
            button.setAccessibilityLabel(icon.accessibilityLabel)
            drawnIcon = icon
        }

        let title = model.settings.percentageStyle == .beside ? snapshot.percentage.formatted(.percent) : ""
        if title != drawnTitle {
            button.attributedTitle = NSAttributedString(
                string: title.isEmpty ? "" : title + " ",
                attributes: [.font: NSFont.menuBarFont(ofSize: 0).monospacedDigits])
            drawnTitle = title
        }
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
