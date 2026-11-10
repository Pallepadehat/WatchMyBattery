import AppKit
import Observation
import SwiftUI

/// Lets you drag an app's slice out of the panel to quit it, the way you'd
/// drag an icon off the Dock.
///
/// The panel can't draw outside its own bounds, so while you drag, the app's
/// icon follows the pointer in a small floating window of its own. Let go
/// outside the panel and it vanishes in a puff of smoke; let go inside and it
/// slides back where it came from.
final class DragToQuitController {
    static let shared = DragToQuitController()

    private(set) var isDragging = false
    /// The drag is far enough outside the panel that letting go would quit.
    private(set) var isArmed = false

    private let ghost = GhostState()
    private var window: NSPanel?
    private var startPoint: CGPoint = .zero
    private var panelFrame: CGRect = .zero

    private static let windowSize = CGSize(width: 180, height: 150)
    /// How far past the panel's edge the pointer has to go.
    private static let armingMargin: CGFloat = 14

    private static let poofSound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/poof item off dock.aif"
        return NSSound(contentsOfFile: path, byReference: true)
    }()

    // MARK: - Driving the drag

    /// Starts following the pointer with the app's icon. `point` is in screen coordinates.
    func begin(_ app: AppUsage, at point: CGPoint, panelFrame: CGRect) {
        isDragging = true
        isArmed = false
        startPoint = point
        self.panelFrame = panelFrame
        ghost.reset(icon: app.icon, name: app.name, tint: app.tint)

        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrameOrigin(origin(for: point))
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    func move(to point: CGPoint) {
        guard isDragging, let window else { return }
        window.setFrameOrigin(origin(for: point))
        let armed = !panelFrame.insetBy(dx: -Self.armingMargin, dy: -Self.armingMargin).contains(point)
        if armed != isArmed {
            isArmed = armed
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { ghost.isArmed = armed }
        }
    }

    /// Ends the drag. Returns `true` when it ended outside the panel, meaning
    /// the app should quit; the icon then goes up in smoke. Otherwise it flies
    /// back to `home` (or where the drag started).
    @discardableResult
    func end(at point: CGPoint, home: CGPoint? = nil, playsSound: Bool = true) -> Bool {
        guard isDragging, let window else { return false }
        move(to: point)
        isDragging = false
        let quits = isArmed
        isArmed = false

        if quits {
            if playsSound { Self.poofSound?.stop(); Self.poofSound?.play() }
            ghost.poofCount += 1
            withAnimation(.easeOut(duration: 0.3)) { ghost.isPoofing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.hide() }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrameOrigin(origin(for: home ?? startPoint))
                window.animator().alphaValue = 0.2
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
        return quits
    }

    /// Drops the drag without quitting anything (when the panel closes underneath it, say).
    func cancel() {
        guard isDragging else { return }
        isDragging = false
        isArmed = false
        hide()
    }

    // MARK: - The floating icon

    private func hide() {
        guard !isDragging else { return }
        window?.orderOut(nil)
    }

    /// Puts the icon's centre under the pointer.
    private func origin(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - Self.windowSize.width / 2, y: point.y - Self.windowSize.height / 2)
    }

    private func makeWindow() -> NSPanel {
        let hosting = NSHostingView(rootView: GhostView(state: ghost))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: Self.windowSize)
        let window = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.windowSize), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu + 1
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hosting
        return window
    }
}

/// What the floating icon shows.
@Observable
final class GhostState {
    var icon: NSImage = NSImage()
    var name = ""
    var tint: Color = .accentColor
    var isArmed = false
    var isPoofing = false
    /// Bumped for each poof, which plays the smoke animation.
    var poofCount = 0

    func reset(icon: NSImage, name: String, tint: Color) {
        self.icon = icon
        self.name = name
        self.tint = tint
        isArmed = false
        isPoofing = false
    }
}
