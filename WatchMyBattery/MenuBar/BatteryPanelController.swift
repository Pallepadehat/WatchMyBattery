import AppKit
import SwiftUI

/// The panel that drops down from the menu bar icon.
///
/// A borderless, non-activating panel rather than an `NSPopover`, so it
/// looks like a native menu (no arrow) and doesn't steal focus from the app
/// you're in. It closes when you click anywhere else.
final class BatteryPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private var panel: BatteryPanel?
    private var outsideClickMonitor: Any?

    var isShown: Bool { panel?.isVisible == true }

    init(model: AppModel, statusItem: NSStatusItem) {
        self.model = model
        self.statusItem = statusItem
    }

    func toggle() {
        isShown ? close() : show()
    }

    func show() {
        guard !isShown else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.panelDidOpen()
        position(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)

        // Clicks in other apps (and on the desktop) close it, the way a menu would.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard let panel, isShown else { return }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        statusItem.button?.highlight(false)
        model.panelDidClose()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    // MARK: - NSWindowDelegate

    /// Clicking our own menu bar icon or another app's window takes key status away.
    func windowDidResignKey(_ notification: Notification) {
        // A drag out of the panel keeps it open until the drop is done.
        guard !DragToQuitController.shared.isDragging else { return }
        close()
    }

    // MARK: - Building and placing

    private func makePanel() -> BatteryPanel {
        let content = BatteryPanelView(model: model, close: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let panel = BatteryPanel(content: hosting)
        panel.delegate = self
        return panel
    }

    /// Under the menu bar icon, the way menus line up, but kept on screen.
    private func position(_ panel: NSPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        var x = buttonFrame.minX
        x = min(x, visible.maxX - size.width - 8)
        x = max(x, visible.minX + 8)
        panel.setFrameTopLeftPoint(CGPoint(x: x, y: buttonFrame.minY - 6))
    }
}

/// A rounded, glassy panel that hosts SwiftUI content and grows downward as
/// its content's height changes, keeping its top edge under the menu bar.
final class BatteryPanel: NSPanel {
    static let cornerRadius: CGFloat = 16

    init(content: NSView) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 320, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false

        let background = Self.makeBackground(around: content)
        contentView = background
        setContentSize(content.fittingSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape closes it, like a menu.
    override func cancelOperation(_ sender: Any?) {
        (delegate as? BatteryPanelController)?.close()
    }

    /// Keeps the top edge where it is when the content resizes the window.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if isVisible, frame.height != self.frame.height {
            frame.origin.y = self.frame.maxY - frame.height
        }
        super.setFrame(frame, display: flag)
    }

    /// Liquid Glass where available, the menu material before that.
    private static func makeBackground(around content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }
}
