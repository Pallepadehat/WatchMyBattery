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
        let panel = BatteryPanel()
        let close: () -> Void = { [weak self] in self?.close() }
        // SwiftUI reports the content's size, and the panel follows it: when an
        // app slice appears or the tip is dismissed, the panel grows or shrinks
        // downward, its top staying under the menu bar.
        let content = BatteryPanelView(model: model, close: close)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { [weak panel] size in
                panel?.fit(contentSize: size)
            }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        // The glass view would otherwise hand its own insets to SwiftUI as a safe area, pushing the content around.
        hosting.safeAreaRegions = []
        panel.install(hosting)
        // The first size, measured up front so the panel opens at the right height.
        panel.setContentSize(
            NSHostingController(rootView: BatteryPanelView(model: model, close: close))
                .sizeThatFits(in: CGSize(width: BatteryPanelView.width, height: 2000)))
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

/// A rounded, glassy panel that hosts SwiftUI content. It grows and shrinks
/// downward, keeping its top edge under the menu bar.
final class BatteryPanel: NSPanel {
    static let cornerRadius: CGFloat = 18

    private var content: NSView?

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: BatteryPanelView.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape closes it, like a menu.
    override func cancelOperation(_ sender: Any?) {
        (delegate as? BatteryPanelController)?.close()
    }

    /// Puts `content` on a Liquid Glass background (the menu material before macOS 26).
    ///
    /// The background sits inside a plain container rather than being the
    /// window's content view itself; AppKit then keeps it sized with the
    /// window through ordinary autoresizing.
    func install(_ content: NSView) {
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            background = glass
            // The window's shadow is worked out as a rectangle around the glass, which shows as square corners.
            hasShadow = false
        } else {
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            background = effect
        }
        background.frame = container.bounds
        background.autoresizingMask = [.width, .height]
        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(background)
        contentView = container
        self.content = content
    }

    /// Resizes to the content, keeping the top edge where it is.
    func fit(contentSize size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard size != frame.size else { return }
        // Not in the middle of SwiftUI's layout pass, which is where size changes are reported.
        DispatchQueue.main.async { [self] in
            let top = frame.maxY
            setFrame(CGRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
            content?.frame = CGRect(origin: .zero, size: size)
            invalidateShadow()
        }
    }
}
