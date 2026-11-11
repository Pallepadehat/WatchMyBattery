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
    /// Where the charging glint is in its sweep, 0–1, or `nil` for a still icon.
    var chargeGlint: Double?
    /// Draw for a dark (`true`) or light menu bar, instead of the one being drawn into.
    /// For previews, like the samples in Settings, which aren't drawn into a menu bar at all.
    var drawsForDarkBar: Bool?

    init(snapshot: BatterySnapshot, settings: AppSettings) {
        self.init(snapshot: snapshot, percentageStyle: settings.percentageStyle, usesColor: settings.usesColor)
    }

    init(snapshot: BatterySnapshot, percentageStyle: PercentageStyle, usesColor: Bool, drawsForDarkBar: Bool? = nil) {
        self.drawsForDarkBar = drawsForDarkBar
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
        let isDarkBar = drawsForDarkBar ?? (NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
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

        if let chargeGlint, chargeState == .charging {
            drawGlint(at: chargeGlint, body: body, bodyPath: bodyPath, fill: fill, terminal: terminal, color: accentColor ?? foreground, context: context)
        }

        // The percentage or a symbol on top: cut out of the charge, so the menu
        // bar shows through, and solid over the empty part. A glyph that sits
        // across the edge of the charge still reads as one clear shape.
        let solid = accentColor == nil ? NSColor.black : foreground
        if showsPercentageInside {
            let text = percentageText(in: body)
            let size = text.size()
            let origin = CGPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2 + 0.25)
            stamp(body: body, fill: fill, solid: solid, context: context) { color in
                let colored = NSMutableAttributedString(attributedString: text)
                colored.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: colored.length))
                colored.draw(at: origin)
            }
        } else if chargeState == .charging {
            let bolt = boltPath(in: body)
            stamp(body: body, fill: fill, solid: solid, context: context) { color in
                color.setFill()
                bolt.fill()
            }
        } else if chargeState == .notCharging {
            let plug = plugPath(in: body)
            stamp(body: body, fill: fill, solid: solid, context: context) { color in
                color.setFill()
                plug.fill()
            }
        }
    }

    /// Draws a glyph twice: punched out of the charge, and in `solid` over the
    /// rest of the pill. `draw` paints the glyph in the colour it's given.
    private func stamp(body: CGRect, fill: CGRect, solid: NSColor, context: CGContext, draw: (NSColor) -> Void) {
        // Punched out of the charge (and anything outside the pill, where there's nothing to punch).
        context.saveGState()
        context.clip(to: [
            CGRect(x: 0, y: 0, width: fill.maxX, height: Self.imageHeight),
            CGRect(x: 0, y: 0, width: Self.imageHeight * 4, height: body.minY),
            CGRect(x: 0, y: body.maxY, width: Self.imageHeight * 4, height: Self.imageHeight - body.maxY),
        ])
        context.setBlendMode(.destinationOut)
        draw(.black)
        context.restoreGState()

        // Solid over the empty part, so it stands out from the translucent pill.
        guard fill.maxX < body.maxX else { return }
        context.saveGState()
        context.clip(to: CGRect(x: fill.maxX, y: body.minY, width: body.maxX - fill.maxX, height: body.height))
        context.setBlendMode(.copy)
        draw(solid)
        context.restoreGState()
    }

    /// Charge flowing in: a soft swell of colour leaves the edge of the charge,
    /// rolls through the empty part of the pill to the terminal, and fades as
    /// it gets there, which gives the terminal a little flash. It only ever
    /// adds the icon's own colour over the translucent part, so it looks the
    /// same in a template icon and a coloured one, on any menu bar.
    private func drawGlint(
        at phase: Double, body: CGRect, bodyPath: NSBezierPath, fill: CGRect, terminal: CGRect, color: NSColor,
        context: CGContext
    ) {
        // Ease in and out, so the swell glides rather than ticks.
        let t = phase < 0.5 ? 2 * phase * phase : 1 - pow(-2 * phase + 2, 2) / 2
        // Fades in as it leaves the charge and out as it reaches the end.
        let strength = CGFloat(sin(Double.pi * phase))
        let empty = CGRect(x: fill.maxX, y: body.minY, width: max(body.maxX - fill.maxX, 0), height: body.height)
        let width = max(min(empty.width * 0.7, 10), 5)
        let center = empty.minX + (empty.width + width / 2) * t
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let space = CGColorSpaceCreateDeviceRGB()

        if empty.width > 0.5,
            let swell = CGGradient(
                colorsSpace: space,
                colors: [0, 0.75, 1, 0.75, 0].map { rgb.withAlphaComponent($0 * 0.75 * strength).cgColor } as CFArray,
                locations: [0, 0.25, 0.5, 0.75, 1])
        {
            context.saveGState()
            bodyPath.addClip()
            context.clip(to: empty)
            context.drawLinearGradient(
                swell, start: CGPoint(x: center - width / 2, y: 0), end: CGPoint(x: center + width / 2, y: 0), options: [])
            context.restoreGState()
        }

        // The terminal lights up as the swell arrives.
        let arrival = min(max((phase - 0.55) / 0.45, 0), 1)
        let flash = CGFloat(sin(Double.pi * arrival))
        if flash > 0 {
            rgb.withAlphaComponent(0.6 * flash).setFill()
            terminalPath(in: terminal).fill()
        }
    }

    /// How strongly the drained part of the pill shows, like the built-in icon.
    private static let emptyOpacity: CGFloat = 0.4

    private func percentageText(in body: CGRect) -> NSAttributedString {
        let fontSize: CGFloat = percentage >= 100 ? 9 : 10.5
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold).monospacedDigits
        return NSAttributedString(string: "\(percentage)", attributes: [.font: font, .foregroundColor: NSColor.black])
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
        let level = (Double(percentage) / 100).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "Battery \(level), \(state)")
    }
}
