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
        // Before anything is measured, so the panel opens already fitting this screen.
        let maxHeight = availableCardHeight()
        let screenChanged = maxHeight != model.panelMaxHeight
        model.panelMaxHeight = maxHeight
        let panel: BatteryPanel
        if let existing = self.panel {
            panel = existing
            // Opened on a shorter (or taller) screen than last time: resize now rather than a frame later.
            if screenChanged { panel.setCardSize(measuredSize()) }
        } else {
            panel = makePanel()
            self.panel = panel
        }
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
        DragToQuitController.shared.cancel()
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
        panel.setCardSize(measuredSize())
        panel.delegate = self
        return panel
    }

    /// The panel's size as SwiftUI lays it out, already held to `model.panelMaxHeight`.
    private func measuredSize() -> CGSize {
        NSHostingController(rootView: BatteryPanelView(model: model, close: {}))
            .sizeThatFits(in: CGSize(width: BatteryPanelView.width, height: 4000))
    }

    /// The gap under the menu bar icon, the way menus line up.
    private static let gapBelowMenuBar: CGFloat = 6
    /// Room left between the panel and the bottom of the screen (or the Dock), so it never touches the edge.
    private static let bottomMargin: CGFloat = 10
    /// Even on the smallest screen, enough for the header, the gauge and the menu items.
    private static let minimumHeight: CGFloat = 280

    private var buttonScreenFrame: (button: CGRect, visible: CGRect)? {
        guard let button = statusItem.button, let buttonWindow = button.window else { return nil }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        return (buttonFrame, screen?.visibleFrame ?? .zero)
    }

    /// How tall the card can be on the screen the menu bar icon is on.
    private func availableCardHeight() -> CGFloat {
        guard let (button, visible) = buttonScreenFrame, visible.height > 0 else { return .infinity }
        let top = button.minY - Self.gapBelowMenuBar
        return max(Self.minimumHeight, floor(top - visible.minY - Self.bottomMargin))
    }

    /// Under the menu bar icon, the way menus line up, but kept on screen.
    private func position(_ panel: BatteryPanel) {
        guard let (button, visible) = buttonScreenFrame else { return }
        let width = panel.cardFrame.width
        var x = button.minX
        x = min(x, visible.maxX - width - 8)
        x = max(x, visible.minX + 8)
        panel.moveCard(topLeft: CGPoint(x: x, y: button.minY - Self.gapBelowMenuBar))
    }
}

/// The rounded glass behind the panel and the AirPods card: Liquid Glass on
/// macOS 26, and a translucent material before it.
enum GlassCard {
    static func make(around content: NSView, cornerRadius: CGFloat, material: NSVisualEffectView.Material) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.addSubview(content)
        return effect
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
        let background = GlassCard.make(around: content, cornerRadius: Self.cornerRadius, material: .menu)
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
