import AppKit
import BatteryKit
import SwiftUI

/// Slides the AirPods card in below the menu bar when headphones connect,
/// and away again after a few seconds.
///
/// The card never takes focus, so it doesn't interrupt typing. It stays
/// while the pointer is over it; clicking it opens the panel.
final class AccessoryCardController {
    private let model: AppModel
    /// The menu bar icon's frame on screen, for placing the card below it.
    private let iconFrame: () -> CGRect?
    private var window: AccessoryCardWindow?
    private var hosting: NSHostingView<LiveAccessoryCard>?
    private var dismissTask: Task<Void, Never>?
    private var isHovered = false
    private var isClosing = false

    /// How far the card travels as it slides in.
    private static let slide: CGFloat = 14
    /// The gap between the menu bar and the card.
    private static let gap: CGFloat = 6

    init(model: AppModel, iconFrame: @escaping () -> CGRect?) {
        self.model = model
        self.iconFrame = iconFrame
    }

    /// Shows the card for `accessory`, or switches the one on screen to it.
    func show(_ accessory: Accessory) {
        let card = LiveAccessoryCard(
            monitor: model.accessories, initial: accessory,
            close: { [weak self] in self?.dismiss() },
            open: { [weak self] in
                self?.dismiss()
                self?.model.showPanel()
            })

        if let window, window.isVisible, !isClosing {
            hosting?.rootView = card
            fit(window)
            scheduleDismiss()
            announce(accessory)
            return
        }

        let window = self.window ?? AccessoryCardWindow()
        window.onHover = { [weak self] hovering in self?.hoverChanged(hovering) }
        self.window = window
        let hosting = NSHostingView(rootView: card)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        window.install(hosting)
        self.hosting = hosting
        isClosing = false
        isHovered = false
        fit(window)

        // In from just above, fading up; Reduce Motion keeps it to the fade.
        let final = window.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(final.offsetBy(dx: 0, dy: reduceMotion ? 0 : Self.slide), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.42
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            window.animator().setFrame(final, display: true)
            window.animator().alphaValue = 1
        }
        scheduleDismiss()
        announce(accessory)
    }

    func dismiss() {
        dismissTask?.cancel()
        guard let window, window.isVisible, !isClosing else { return }
        isClosing = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            if !reduceMotion { window.animator().setFrame(window.frame.offsetBy(dx: 0, dy: Self.slide / 2), display: true) }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isClosing else { return }
                window.orderOut(nil)
                self.isClosing = false
            }
        }
    }

    // MARK: - Staying, going

    private func scheduleDismiss(after seconds: Double? = nil) {
        dismissTask?.cancel()
        let seconds = seconds ?? Double(model.settings.accessoryCardDuration)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.isHovered else { return }
            self.dismiss()
        }
    }

    /// The card waits while the pointer is over it, and goes soon after it leaves.
    private func hoverChanged(_ hovering: Bool) {
        isHovered = hovering
        if hovering {
            dismissTask?.cancel()
        } else {
            scheduleDismiss(after: 2)
        }
    }

    /// VoiceOver reads it out, as the card doesn't take focus.
    private func announce(_ accessory: Accessory) {
        let parts = accessory.displayParts.map(\.spokenDescription).joined(separator: ", ")
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [
                .announcement: String(localized: "\(accessory.name) connected. \(parts)"),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
    }

    // MARK: - Placing

    /// Sizes the window to the card and puts it where Settings says.
    private func fit(_ window: AccessoryCardWindow) {
        guard let hosting else { return }
        // Measured up front, as the panel is: the hosting view itself doesn't report a size until it's been laid out.
        let size = NSHostingController(rootView: hosting.rootView).sizeThatFits(in: CGSize(width: AccessoryCard.width, height: 1000))
        window.setCardSize(CGSize(width: AccessoryCard.width, height: size.height))

        let icon = iconFrame()
        let screen = screen(for: icon)
        let visible = screen.visibleFrame
        let width = AccessoryCard.width
        var x: CGFloat
        switch model.settings.accessoryCardPosition {
        case .belowIcon:
            // Centred under the icon, like a popover; the right edge when the icon is on another screen.
            if let icon, screen.frame.contains(CGPoint(x: icon.midX, y: icon.midY)) {
                x = icon.midX - width / 2
            } else {
                x = visible.maxX - width - 10
            }
        case .topCenter:
            x = visible.midX - width / 2
        case .topRight:
            x = visible.maxX - width - 10
        }
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        window.moveCard(topLeft: CGPoint(x: x, y: visible.maxY - Self.gap))
    }

    /// The screen with the menu bar icon, which is the one with the active menu bar.
    private func screen(for icon: CGRect?) -> NSScreen {
        if let icon, let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: icon.midX, y: icon.midY)) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

/// The card, kept up to date: levels often arrive a moment after the earbuds connect.
struct LiveAccessoryCard: View {
    let monitor: AccessoryMonitor
    let initial: Accessory
    let close: () -> Void
    let open: () -> Void

    var body: some View {
        let accessory = monitor.accessories.first { $0.id == initial.id } ?? initial
        AccessoryCard(accessory: accessory, close: close, open: open)
            // A new card for new headphones, so its rings fill up again.
            .id(initial.id)
    }
}

/// A floating glass card that never takes focus, with room around it for its shadow.
final class AccessoryCardWindow: NSPanel {
    static let cornerRadius: CGFloat = 22
    static let margin: CGFloat = 24

    private var content: NSView?
    /// The pointer moved onto the card or off it.
    var onHover: (Bool) -> Void = { _ in }

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: AccessoryCard.width + Self.margin * 2, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func install(_ content: NSView) {
        // SwiftUI's hover tracking only follows the active app; this follows the pointer whatever is active.
        let container = HoverTrackingView(frame: CGRect(origin: .zero, size: frame.size), inset: Self.margin) { [weak self] in
            self?.onHover($0)
        }
        let background = GlassCard.make(around: content, cornerRadius: Self.cornerRadius, material: .hudWindow)
        background.frame = container.bounds.insetBy(dx: Self.margin, dy: Self.margin)
        background.autoresizingMask = [.width, .height]
        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(background)
        contentView = container
        self.content = content
    }

    func setCardSize(_ size: CGSize) {
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        let top = frame.maxY
        setFrame(
            CGRect(x: frame.minX, y: top - size.height - Self.margin * 2, width: size.width + Self.margin * 2, height: size.height + Self.margin * 2),
            display: true)
        content?.frame = CGRect(origin: .zero, size: size)
    }

    func moveCard(topLeft point: CGPoint) {
        setFrameTopLeftPoint(CGPoint(x: point.x - Self.margin, y: point.y + Self.margin))
    }
}

/// Reports the pointer entering and leaving the card (the view inset by its shadow margin), even while another app is active.
private final class HoverTrackingView: NSView {
    private let inset: CGFloat
    private let onHover: (Bool) -> Void
    private var trackingArea: NSTrackingArea?

    init(frame: CGRect, inset: CGFloat, onHover: @escaping (Bool) -> Void) {
        self.inset = inset
        self.onHover = onHover
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("Not used from a nib") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds.insetBy(dx: inset, dy: inset), options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}
