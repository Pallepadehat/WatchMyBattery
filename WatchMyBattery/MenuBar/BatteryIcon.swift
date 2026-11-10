import AppKit
import BatteryKit

/// Draws the battery that sits in the menu bar.
///
/// It looks like the built-in one: a solid rounded pill with a little
/// terminal, bright as far as the battery is charged and translucent beyond,
/// with a bolt cut out of it while charging. It can also print the percentage
/// inside, cut out the same way, so it stays readable on any wallpaper.
struct BatteryIcon: Equatable {
    var level: Double
    var percentage: Int
    var chargeState: BatterySnapshot.ChargeState
    var showsPercentageInside: Bool
    var usesColor: Bool
    var isLowPowerModeOn: Bool

    init(snapshot: BatterySnapshot, settings: AppSettings) {
        self.init(snapshot: snapshot, percentageStyle: settings.percentageStyle, usesColor: settings.usesColor)
    }

    init(snapshot: BatterySnapshot, percentageStyle: PercentageStyle, usesColor: Bool) {
        level = snapshot.level
        percentage = snapshot.percentage
        chargeState = snapshot.chargeState
        showsPercentageInside = percentageStyle == .inside
        self.usesColor = usesColor
        isLowPowerModeOn = snapshot.isLowPowerModeOn
    }

    /// At or below this, the battery counts as low.
    static let lowPercentage = 20

    // MARK: Geometry (points)

    private var bodySize: CGSize { CGSize(width: 23, height: 12) }
    private static let terminalSize = CGSize(width: 1.5, height: 4)
    private static let terminalGap: CGFloat = 1
    private static let imageHeight: CGFloat = 16

    // MARK: Colours

    private enum Accent {
        case none, charging, lowPower, low
    }

    private var accent: Accent {
        guard usesColor else { return .none }
        if chargeState == .charging { return .charging }
        if isLowPowerModeOn { return .lowPower }
        if chargeState == .discharging && percentage <= Self.lowPercentage { return .low }
        return .none
    }

    private static func color(for accent: Accent) -> NSColor? {
        switch accent {
        case .none: nil
        case .charging: .systemGreen
        case .lowPower: .systemYellow
        case .low: .systemRed
        }
    }

    // MARK: Drawing

    /// A monochrome icon is a template image, so the menu bar tints it for
    /// light and dark wallpapers itself. A coloured one draws its own outline
    /// in the label colour, which resolves against the menu bar's appearance.
    func image() -> NSImage {
        let body = bodySize
        let size = CGSize(width: ceil(body.width + Self.terminalGap + Self.terminalSize.width), height: Self.imageHeight)
        let accentColor = Self.color(for: accent)
        let image = NSImage(size: size, flipped: false) { _ in
            draw(in: size, accentColor: accentColor)
            return true
        }
        image.isTemplate = accentColor == nil
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    private func draw(in size: CGSize, accentColor: NSColor?) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // A template only needs alpha; a coloured icon picks white or black for the menu bar it's drawn in.
        let isDarkBar = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let foreground: NSColor = accentColor == nil || !isDarkBar ? .black : .white
        let empty = foreground.withAlphaComponent(Self.emptyOpacity)
        let body = CGRect(
            x: 0, y: ((size.height - bodySize.height) / 2).rounded(), width: bodySize.width, height: bodySize.height)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodySize.height * 0.38, yRadius: bodySize.height * 0.38)

        // The terminal: a small half-round nub.
        empty.setFill()
        let terminal = CGRect(
            x: body.maxX + Self.terminalGap, y: body.midY - Self.terminalSize.height / 2,
            width: Self.terminalSize.width, height: Self.terminalSize.height)
        terminalPath(in: terminal).fill()

        // A solid pill: the charge in full colour, the rest translucent.
        // Always show a sliver, so an almost empty battery still reads as a battery.
        let fillWidth = level > 0 ? max(body.width * level, 3) : 0
        let fill = CGRect(x: body.minX, y: body.minY, width: fillWidth, height: body.height)
        context.saveGState()
        bodyPath.addClip()
        empty.setFill()
        body.fill()
        (accentColor ?? foreground).setFill()
        fill.fill()
        context.restoreGState()

        // What goes on top is cut out of the pill, so the menu bar shows through.
        if showsPercentageInside {
            cutOut(percentageText(in: body), context: context)
        } else if chargeState == .charging {
            cutOut(boltPath(in: body), context: context)
        } else if chargeState == .notCharging {
            cutOut(plugPath(in: body), context: context)
        }
    }

    /// How strongly the drained part of the pill shows, like the built-in icon.
    private static let emptyOpacity: CGFloat = 0.4

    private func percentageText(in body: CGRect) -> NSAttributedString {
        let fontSize: CGFloat = percentage >= 100 ? 9 : 10.5
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold).monospacedDigits
        return NSAttributedString(string: "\(percentage)", attributes: [.font: font, .foregroundColor: NSColor.black])
    }

    private func cutOut(_ text: NSAttributedString, context: CGContext) {
        let body = CGRect(
            x: 0, y: ((Self.imageHeight - bodySize.height) / 2).rounded(), width: bodySize.width, height: bodySize.height)
        let textSize = text.size()
        context.saveGState()
        context.setBlendMode(.destinationOut)
        text.draw(at: CGPoint(x: body.midX - textSize.width / 2, y: body.midY - textSize.height / 2 + 0.25))
        context.restoreGState()
    }

    private func cutOut(_ path: NSBezierPath, context: CGContext) {
        context.saveGState()
        context.setBlendMode(.destinationOut)
        NSColor.black.setFill()
        path.fill()
        context.restoreGState()
    }

    private func terminalPath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.appendArc(
            withCenter: CGPoint(x: rect.minX, y: rect.midY), radius: rect.height / 2, startAngle: -90, endAngle: 90)
        path.close()
        return path
    }

    private func boltPath(in body: CGRect) -> NSBezierPath {
        let height = body.height + 3
        let width = height * 0.6
        let x = body.midX - width / 2
        let y = body.midY - height / 2
        let points: [(CGFloat, CGFloat)] = [
            (0.62, 1), (0.08, 0.42), (0.47, 0.42), (0.38, 0), (0.92, 0.58), (0.53, 0.58),
        ]
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: x + point.0 * width, y: y + point.1 * height)
            index == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.close()
        return path
    }

    private func plugPath(in body: CGRect) -> NSBezierPath {
        let center = CGPoint(x: body.midX, y: body.midY)
        let path = NSBezierPath(
            roundedRect: CGRect(x: center.x - 3, y: center.y - 2.5, width: 6, height: 4.5), xRadius: 1.5, yRadius: 1.5)
        path.append(NSBezierPath(rect: CGRect(x: center.x - 2, y: center.y + 2, width: 1, height: 2.5)))
        path.append(NSBezierPath(rect: CGRect(x: center.x + 1, y: center.y + 2, width: 1, height: 2.5)))
        path.append(NSBezierPath(rect: CGRect(x: center.x - 0.75, y: center.y - 4.5, width: 1.5, height: 2.5)))
        return path
    }

    var accessibilityLabel: String {
        let state: String =
            switch chargeState {
            case .charging: String(localized: "charging")
            case .charged: String(localized: "fully charged")
            case .notCharging: String(localized: "not charging")
            case .discharging: String(localized: "on battery")
            }
        return String(localized: "Battery \(percentage)%, \(state)")
    }
}
