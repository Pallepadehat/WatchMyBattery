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
        panel.setCardSize(
            NSHostingController(rootView: BatteryPanelView(model: model, close: close))
                .sizeThatFits(in: CGSize(width: BatteryPanelView.width, height: 2000)))
        panel.delegate = self
        return panel
    }

    /// Under the menu bar icon, the way menus line up, but kept on screen.
    private func position(_ panel: BatteryPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let width = panel.cardFrame.width
        var x = buttonFrame.minX
        x = min(x, visible.maxX - width - 8)
        x = max(x, visible.minX + 8)
        panel.moveCard(topLeft: CGPoint(x: x, y: buttonFrame.minY - 6))
    }
}

/// A rounded, glassy panel that hosts SwiftUI content. It grows and shrinks
/// downward, keeping its top edge under the menu bar.
///
/// The visible card sits inside the window with a transparent margin around
/// it, so the glass's soft shadow has room to fade out instead of being cut
/// off square at the window's edges.
final class BatteryPanel: NSPanel {
    static let cornerRadius: CGFloat = 18
    /// Room around the card for its shadow. Clicks there pass through to whatever's behind.
    static let margin: CGFloat = 24

    private var content: NSView?

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: BatteryPanelView.width + Self.margin * 2, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The glass (or the material below macOS 26) draws its own rounded shadow.
        hasShadow = false
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

    /// The visible card, in screen coordinates.
    var cardFrame: CGRect { frame.insetBy(dx: Self.margin, dy: Self.margin) }

    /// Puts `content` on a Liquid Glass card (the menu material before macOS 26).
    func install(_ content: NSView) {
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            background = glass
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
        background.frame = container.bounds.insetBy(dx: Self.margin, dy: Self.margin)
        background.autoresizingMask = [.width, .height]
        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(background)
        contentView = container
        self.content = content
    }

    /// Sizes the card, keeping the top edge where it is.
    func setCardSize(_ size: CGSize) {
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        let windowSize = CGSize(width: size.width + Self.margin * 2, height: size.height + Self.margin * 2)
        let top = frame.maxY
        setFrame(CGRect(x: frame.minX, y: top - windowSize.height, width: windowSize.width, height: windowSize.height), display: true)
        content?.frame = CGRect(origin: .zero, size: size)
    }

    /// Puts the card's top-left corner at `point`.
    func moveCard(topLeft point: CGPoint) {
        setFrameTopLeftPoint(CGPoint(x: point.x - Self.margin, y: point.y + Self.margin))
    }

    /// Follows the content's size as SwiftUI reports it.
    func fit(contentSize size: CGSize) {
        guard size.width > 0, size.height > 0, CGSize(width: ceil(size.width), height: ceil(size.height)) != cardFrame.size
        else { return }
        // Not in the middle of SwiftUI's layout pass, which is where size changes are reported.
        DispatchQueue.main.async { [self] in setCardSize(size) }
    }
}
