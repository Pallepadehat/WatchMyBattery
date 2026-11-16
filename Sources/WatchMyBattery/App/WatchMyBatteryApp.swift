import AppKit
import BatteryKit

/// WatchMyBattery lives in the menu bar: no Dock icon, no main window.
/// (`LSUIElement` is set in the build settings.)
///
/// It's a plain AppKit app rather than a SwiftUI `App`, because everything
/// hangs off an `NSStatusItem` and a custom panel, which need more control
/// than `MenuBarExtra` gives.
@main
enum WatchMyBatteryApp {
    static func main() {
        #if DEBUG
            PreviewRenderer.runIfRequested()
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(settings: .forLaunch())
    private var statusItem: StatusItemController?
    private var accessoryCard: AccessoryCardController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(model: model)
        model.showPanel = { [weak self] in self?.statusItem?.showPanel() }
        model.togglePanel = { [weak self] in self?.statusItem?.togglePanel() }
        let accessoryCard = AccessoryCardController(model: model) { [weak self] in self?.statusItem?.iconFrame }
        self.accessoryCard = accessoryCard
        model.showAccessoryCard = { [weak accessoryCard] in accessoryCard?.show($0) }
        model.start()
        #if DEBUG
            if CommandLine.arguments.contains("--show-settings") {
                // `--settings-pane updates` (say) opens that pane.
                let arguments = CommandLine.arguments
                let pane = arguments.firstIndex(of: "--settings-pane").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                model.openSettings(pane.flatMap(SettingsPane.init(rawValue:)))
                // `--check-now` presses Check Now, once Sparkle is ready (with `--start-updater`).
                if arguments.contains("--check-now") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.model.updater.checkNow() }
                }
                return
            }
            if CommandLine.arguments.contains("--show-accessory-card") {
                // `--show-accessory-card` slides in the card for the first headphones (add `--pretend-accessories` for made-up ones).
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let headphones = self.model.accessories.accessories.first(where: { $0.kind.isAudio }) {
                        self.model.showAccessoryCard(headphones)
                    }
                }
                return
            }
        #endif
        if LaunchOptions.showsPanel {
            // Give the menu bar a moment to place the icon, so the panel lines up under it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.statusItem?.showPanel() }
            return
        }
        if !model.settings.hasSeenWelcome {
            model.settings.hasSeenWelcome = true
            statusItem?.showPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    /// Opening the app again (from Finder or Spotlight) shows the panel, since there's no window to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPanel()
        return false
    }
}
