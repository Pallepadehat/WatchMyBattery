import AppKit
import SwiftUI

/// The welcome tour's window: borderless, so the tour's own rounded glass is the whole window, and draggable by its
/// background. Like Settings, the app steps forward while it's open, so it can take focus.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(at step: OnboardingView.Step = .welcome) {
        // A fresh tour every time, starting with its opening.
        window?.close()
        let window = makeWindow(at: step)
        self.window = window
        window.center()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        close()
        model.showPanel()
    }

    private func close() {
        model.settings.hasCompletedOnboarding = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = nil
    }

    private func makeWindow(at step: OnboardingView.Step) -> NSWindow {
        let view = OnboardingView(
            model: model, startingAt: step, finish: { [weak self] in self?.finish() }, close: { [weak self] in self?.close() })
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        let window = OnboardingWindow(contentViewController: controller)
        window.setContentSize(OnboardingIntro<EmptyView, EmptyView>.size)
        window.delegate = self
        return window
    }
}

/// Borderless, transparent around the tour's rounded glass, and still able to take key focus for its controls.
private final class OnboardingWindow: NSWindow {
    convenience init(contentViewController: NSViewController) {
        self.init(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        title = String(localized: "Welcome to WatchMyBattery")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
