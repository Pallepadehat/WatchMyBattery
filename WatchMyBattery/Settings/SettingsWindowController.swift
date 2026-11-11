import AppKit
import SwiftUI

/// The Settings window. A menu bar app has no Settings menu item to hang a
/// SwiftUI `Settings` scene from, so it's an ordinary window we manage.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.launchAtLogin.refresh()
        if !window.isVisible { window.center() }
        // An accessory app has to step forward for its window to take focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to living only in the menu bar.
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        controller.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "WatchMyBattery Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(CGSize(width: 720, height: min(580, (NSScreen.main?.visibleFrame.height ?? 700) - 80)))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("WatchMyBatterySettings")
        #if DEBUG
            // `--tall-settings` opens it tall enough to see a whole pane at once, for screenshots.
            if CommandLine.arguments.contains("--tall-settings") { window.setContentSize(CGSize(width: 720, height: 900)) }
        #endif
        window.delegate = self
        return window
    }
}
