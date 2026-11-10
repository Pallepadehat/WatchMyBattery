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
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "WatchMyBattery Settings")
        // Resizable in height only; the form scrolls when it's taller than the window.
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(CGSize(width: 460, height: min(560, (NSScreen.main?.visibleFrame.height ?? 700) - 80)))
        window.contentMinSize = CGSize(width: 460, height: 420)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.contentMaxSize = CGSize(width: 460, height: 2000)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
