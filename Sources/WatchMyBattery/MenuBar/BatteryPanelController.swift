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
            // Opened on a shorter (or taller) screen than last time: make room for it before it shows.
            if screenChanged { panel.makeRoom(forCardHeight: maxHeight) }
        } else {
            panel = makePanel(maxHeight: maxHeight)
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

    private func makePanel(maxHeight: CGFloat) -> BatteryPanel {
        let panel = BatteryPanel()
        let close: () -> Void = { [weak self] in self?.close() }
        // The window is as tall as the card can ever be, and the card is drawn and sized by SwiftUI at its top. So
        // when a row comes or goes, the card's edge animates along with its content, in the same animation, instead of
        // the window snapping to a new size while the content is still on its way.
        let content = PanelCard(model: model, close: close) { [weak panel] size in panel?.cardSize = size }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        panel.install(hosting)
        panel.makeRoom(forCardHeight: maxHeight)
        panel.delegate = self
        return panel
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

/// The rounded glass behind the AirPods card: Liquid Glass on macOS 26, and a translucent material before it. (The
/// panel draws its own in SwiftUI; see ``PanelCard``.)
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

/// A transparent window under the menu bar icon, with room for the tallest the panel's card can be. The card sits at
/// its top, drawn by SwiftUI (``PanelCard``); the window never resizes while it's open, so nothing jumps.
///
/// Everything around the card is transparent, so clicks there pass through to whatever's behind, as they do on the
/// margin left for the glass's soft shadow.
final class BatteryPanel: NSPanel {
    static let cornerRadius: CGFloat = 18
    /// Room around the card for its shadow.
    static let margin: CGFloat = 24
    /// Room for the card when the screen gives no limit (the previews' windowless case never gets here).
    private static let fallbackCardHeight: CGFloat = 900

    /// The card's size, as SwiftUI lays it out.
    var cardSize = CGSize(width: BatteryPanelView.width, height: 300)

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: BatteryPanelView.width + Self.margin * 2, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own rounded shadow.
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

    /// The visible card, in screen coordinates: for telling when a slice is dragged out of it.
    var cardFrame: CGRect {
        CGRect(
            x: frame.minX + Self.margin, y: frame.maxY - Self.margin - cardSize.height, width: cardSize.width, height: cardSize.height)
    }

    func install(_ content: NSView) {
        contentView = content
    }

    /// Makes the window tall enough for a card this tall, keeping its top edge where it is.
    func makeRoom(forCardHeight height: CGFloat) {
        let cardHeight = height.isFinite ? height : Self.fallbackCardHeight
        let size = CGSize(width: BatteryPanelView.width + Self.margin * 2, height: ceil(cardHeight) + Self.margin * 2)
        setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: false)
    }

    /// Puts the card's top-left corner at `point`.
    func moveCard(topLeft point: CGPoint) {
        setFrameTopLeftPoint(CGPoint(x: point.x - Self.margin, y: point.y + Self.margin))
    }
}

/// The panel as it appears on screen: ``BatteryPanelView`` on a rounded glass card, at the top of its window, with
/// room around it for the shadow. The card's size is reported as it changes, for ``BatteryPanel/cardFrame``.
private struct PanelCard: View {
    let model: AppModel
    let close: () -> Void
    let sizeChanged: (CGSize) -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: BatteryPanel.cornerRadius, style: .continuous) }

    var body: some View {
        BatteryPanelView(model: model, close: close)
            .modifier(PanelGlass(shape: shape))
            .onGeometryChange(for: CGSize.self, of: \.size, action: sizeChanged)
            .padding(BatteryPanel.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Liquid Glass on macOS 26; before it, the menu's translucent material with a hairline edge and a soft shadow.
private struct PanelGlass: ViewModifier {
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .clipShape(shape)
                // Tinted with the window's own background, so a busy window behind the panel doesn't show through
                // its text, as clear glass let it.
                .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.55)), in: shape)
        } else {
            content
                .background(MenuMaterial())
                .clipShape(shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
    }
}

/// The menu's own translucent material, which SwiftUI's materials don't quite match.
private struct MenuMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
