import AppKit

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
    private let model = AppModel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        statusItem = StatusItemController(model: model)
        model.showPanel = { [weak self] in self?.statusItem?.showPanel() }
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
            if CommandLine.arguments.contains("--show-panel") {
                // Give the menu bar a moment to place the icon, so the panel lines up under it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.statusItem?.showPanel() }
                return
            }
        #endif
        if !model.settings.hasSeenWelcome {
            model.settings.hasSeenWelcome = true
            statusItem?.showPanel()
        }
    }

    /// Opening the app again (from Finder or Spotlight) shows the panel, since there's no window to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPanel()
        return false
    }
}
