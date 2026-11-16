import AppKit
import BatteryKit

/// Draws the battery that sits in the menu bar, in one of its styles.
///
/// The battery looks like the built-in one: a solid rounded pill with a little
/// terminal, bright as far as the battery is charged and translucent beyond,
/// with a bolt cut out of it while charging. It can also print the percentage
/// inside, cut out the same way, so it stays readable on any wallpaper. The
/// ring and the text-only style are drawn in `BatteryIcon+Styles.swift`.
struct BatteryIcon: Hashable {
    var style: MenuBarIconStyle
    var level: Double
    var percentage: Int
    var chargeState: BatterySnapshot.ChargeState
    var showsPercentageInside: Bool
    var usesColor: Bool
    var isLowPowerModeOn: Bool
    /// The level macOS charges to, 0–1: where the charging glint comes to rest.
    var chargeTarget: Double
    /// Where the animation is, 0–1: the charging glint's sweep while charging, the resting shimmer while holding the
    /// charge (see ``ChargingAnimator``), or `nil` for a still icon.
    var animationPhase: Double?
    /// Draw for a dark (`true`) or light menu bar, instead of the one being drawn into.
    /// For previews, like the samples in Settings, which aren't drawn into a menu bar at all.
    var drawsForDarkBar: Bool?

    init(snapshot: BatterySnapshot, settings: AppSettings) {
        self.init(
            snapshot: snapshot, style: settings.menuBarIconStyle, showsPercentageInside: settings.showsPercentageInside,
            usesColor: settings.usesColor)
    }

    init(
        snapshot: BatterySnapshot, style: MenuBarIconStyle = .battery, showsPercentageInside: Bool = false, usesColor: Bool,
        drawsForDarkBar: Bool? = nil
    ) {
        self.style = style
        self.drawsForDarkBar = drawsForDarkBar
        level = snapshot.level
        percentage = snapshot.percentage
        chargeState = snapshot.chargeState
        // Only the battery has room for it.
        self.showsPercentageInside = style == .battery && showsPercentageInside
        self.usesColor = usesColor
        isLowPowerModeOn = snapshot.isLowPowerModeOn
        chargeTarget = Double(snapshot.chargeTarget) / 100
    }

    /// At or below this, the battery counts as low.
    static let lowPercentage = 20

    // MARK: Geometry (points)

    /// The width of the battery's body, which the charging glint sweeps across.
    static let bodyWidth: CGFloat = 23
    private var bodySize: CGSize { CGSize(width: Self.bodyWidth, height: 12) }
    private static let terminalSize = CGSize(width: 1.5, height: 4)
    private static let terminalGap: CGFloat = 1
    static let imageHeight: CGFloat = 16

    /// How wide the image is, for each style.
    private var imageWidth: CGFloat {
        switch style {
        case .battery: ceil(bodySize.width + Self.terminalGap + Self.terminalSize.width)
        case .ring: Self.ringSize
        case .textOnly: hasStateGlyph ? Self.glyphWidth : 0
        }
    }

    /// Text only, with nothing to add to the text: no image at all.
    var isEmpty: Bool { imageWidth == 0 }

    /// Charging shows a bolt, and holding its charge a plug.
    var hasStateGlyph: Bool { chargeState == .charging || chargeState == .notCharging }

    // MARK: Colours

    enum Accent {
        case none, charging, lowPower, low
    }

    var accent: Accent {
        guard usesColor else { return .none }
        if chargeState == .charging { return .charging }
        if isLowPowerModeOn { return .lowPower }
        if chargeState == .discharging && percentage <= Self.lowPercentage { return .low }
        return .none
    }

    static func color(for accent: Accent) -> NSColor? {
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
        let size = CGSize(width: max(imageWidth, 1), height: Self.imageHeight)
        let accentColor = Self.color(for: accent)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let palette = Palette(accent: accentColor, drawsForDarkBar: drawsForDarkBar)
            switch style {
            case .battery: drawBattery(in: size, palette: palette, context: context)
            case .ring: drawRing(in: size, palette: palette, context: context)
            case .textOnly: drawStateGlyph(in: size, palette: palette)
            }
            return true
        }
        image.isTemplate = accentColor == nil
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    /// The colours one image is drawn in.
    struct Palette {
        /// The state's colour, or `nil` for a monochrome (template) icon.
        let accent: NSColor?
        /// The outline and anything not in the accent: black in a template, which the menu bar tints itself; in a
        /// coloured icon, white or black for the menu bar it's drawn in.
        let foreground: NSColor

        init(accent: NSColor?, drawsForDarkBar: Bool?) {
            self.accent = accent
            let isDarkBar = drawsForDarkBar ?? (NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            foreground = accent == nil || !isDarkBar ? .black : .white
        }

        /// The charge: the accent, or the foreground when there's none.
        var charge: NSColor { accent ?? foreground }
        /// The drained part, translucent like the built-in icon's.
        var empty: NSColor { foreground.withAlphaComponent(BatteryIcon.emptyOpacity) }
        /// A glyph over the drained part, where it should stand out.
        var solid: NSColor { accent == nil ? .black : foreground }
    }

    private func drawBattery(in size: CGSize, palette: Palette, context: CGContext) {
        let accentColor = palette.accent
        let foreground = palette.foreground
        let empty = palette.empty
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
        let fillWidth = CGFloat(ChargingGlint.fillWidth(bodyWidth: body.width, level: level))
        let fill = CGRect(x: body.minX, y: body.minY, width: fillWidth, height: body.height)
        context.saveGState()
        bodyPath.addClip()
        empty.setFill()
        body.fill()
        // Copied rather than laid over the empty part, so the charge's own brightness shows: it breathes while it's held.
        (accentColor ?? foreground).withAlphaComponent(chargeOpacity).setFill()
        context.setBlendMode(.copy)
        fill.fill()
        context.restoreGState()

        if let animationPhase, chargeState == .charging {
            drawGlint(at: animationPhase, body: body, bodyPath: bodyPath, fill: fill, terminal: terminal, color: palette.charge, context: context)
        }

        // The percentage or a symbol on top: cut out of the charge, so the menu
        // bar shows through, and solid over the empty part. A glyph that sits
        // across the edge of the charge still reads as one clear shape.
        let solid = palette.solid
        if showsPercentageInside {
            let text = percentageText()
            let size = text.size()
            let origin = CGPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2 + 0.25)
            stamp(body: body, fill: fill, solid: solid, context: context) { color in
                let colored = NSMutableAttributedString(attributedString: text)
                colored.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: colored.length))
                colored.draw(at: origin)
            }
        } else if chargeState == .charging {
            let bolt = Self.boltPath(height: body.height + 3, center: CGPoint(x: body.midX, y: body.midY))
            stamp(body: body, fill: fill, solid: solid, context: context) { color in
                color.setFill()
                bolt.fill()
            }
        } else if chargeState == .notCharging {
            let plug = Self.plugPath(center: CGPoint(x: body.midX, y: body.midY))
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
    /// same in a template icon and a coloured one, on any menu bar. Where it
    /// is in each frame comes from ``ChargingGlint``, which also picks the frames.
    private func drawGlint(
        at phase: Double, body: CGRect, bodyPath: NSBezierPath, fill: CGRect, terminal: CGRect, color: NSColor,
        context: CGContext
    ) {
        let glint = ChargingGlint.frame(at: phase, bodyWidth: body.width, level: level, target: chargeTarget)
        let strength = CGFloat(glint.strength)
        let empty = CGRect(x: fill.maxX, y: body.minY, width: max(body.maxX - fill.maxX, 0), height: body.height)
        let width = CGFloat(glint.width)
        let center = body.minX + CGFloat(glint.center)
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

        // The end lights up as the swell arrives: the terminal when charging to full, or a soft line at the target,
        // where macOS will hold the charge.
        let flash = CGFloat(glint.flash)
        if flash > 0 {
            if chargeTarget >= 1 {
                rgb.withAlphaComponent(0.6 * flash).setFill()
                terminalPath(in: terminal).fill()
            } else {
                let x = body.minX + CGFloat(ChargingGlint.targetPosition(bodyWidth: body.width, target: chargeTarget))
                context.saveGState()
                bodyPath.addClip()
                if let glow = CGGradient(
                    colorsSpace: space, colors: [0, 1, 0].map { rgb.withAlphaComponent($0 * 0.7 * flash).cgColor } as CFArray,
                    locations: [0, 0.5, 1])
                {
                    context.drawLinearGradient(glow, start: CGPoint(x: x - 2.5, y: 0), end: CGPoint(x: x + 2.5, y: 0), options: [])
                }
                context.restoreGState()
            }
        }
    }

    /// How bright the charge is: full, or a little dimmed while it breathes (plugged in, holding its charge).
    var chargeOpacity: CGFloat {
        guard let animationPhase, chargeState == .notCharging else { return 1 }
        return CGFloat(1 - Breathing.depth * Breathing.dimming(at: animationPhase))
    }

    /// How strongly the drained part of the pill shows, like the built-in icon.
    static let emptyOpacity: CGFloat = 0.4

    private func percentageText() -> NSAttributedString {
        let font = percentage >= 100 ? Self.smallDigits : Self.digits
        return NSAttributedString(string: "\(percentage)", attributes: [.font: font, .foregroundColor: NSColor.black])
    }

    /// Made once: building a font with monospaced digits goes through font descriptors, on every frame otherwise.
    private static let digits = NSFont.systemFont(ofSize: 10.5, weight: .semibold).monospacedDigits
    /// "100" needs a size smaller to fit.
    private static let smallDigits = NSFont.systemFont(ofSize: 9, weight: .semibold).monospacedDigits

    private func terminalPath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.appendArc(
            withCenter: CGPoint(x: rect.minX, y: rect.midY), radius: rect.height / 2, startAngle: -90, endAngle: 90)
        path.close()
        return path
    }

    /// A lightning bolt `height` points tall.
    static func boltPath(height: CGFloat, center: CGPoint) -> NSBezierPath {
        let width = height * 0.6
        let x = center.x - width / 2
        let y = center.y - height / 2
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

    /// A plug: plugged in, but holding its charge.
    static func plugPath(center: CGPoint) -> NSBezierPath {
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
