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
