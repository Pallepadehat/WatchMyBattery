import AppKit
import BatteryKit

/// The ring and text-only styles of the menu bar icon. They share the battery's colours (``BatteryIcon/Palette``),
/// glyphs and charging glint, so all three behave alike.
extension BatteryIcon {
    // MARK: Geometry (points)

    /// The ring's image is square, as tall as the menu bar's icons.
    static let ringSize: CGFloat = 16
    private static let ringLineWidth: CGFloat = 2.5
    private static var ringRadius: CGFloat { (ringSize - ringLineWidth) / 2 - 0.5 }
    /// The ring's length, which the charging glint travels along, as it does across the battery's body.
    private static var ringLength: CGFloat { 2 * .pi * ringRadius }
    /// The shortest arc the charge is drawn with, so an almost empty ring still shows some.
    private static let minimumChargeDegrees: CGFloat = 10

    /// Text only has room for a glyph beside the text, nothing more.
    static let glyphWidth: CGFloat = 9

    // MARK: The ring

    /// A ring that fills clockwise from the top as the battery charges, like the AirPods card's, with the bolt or
    /// the plug in the middle.
    func drawRing(in size: CGSize, palette: Palette, context: CGContext) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: Self.ringRadius, startAngle: 0, endAngle: 360)
        track.lineWidth = Self.ringLineWidth
        palette.empty.setStroke()
        track.stroke()

        if level > 0 {
            let sweep = max(CGFloat(level) * 360, Self.minimumChargeDegrees)
            let charge = arc(around: center, from: 0, to: sweep / 360 * Self.ringLength)
            charge.lineCapStyle = .round
            palette.charge.setStroke()
            charge.stroke()
        }

        if let chargeGlint, chargeState == .charging {
            drawRingGlint(at: chargeGlint, center: center, color: palette.charge, context: context)
        }

        switch chargeState {
        case .charging:
            palette.charge.setFill()
            Self.boltPath(height: 8, center: center).fill()
        case .notCharging:
            palette.charge.setFill()
            let plug = Self.plugPath(center: .zero)
            var transform = AffineTransform(translationByX: center.x, byY: center.y)
            transform.scale(0.75)
            plug.transform(using: transform)
            plug.fill()
        case .charged, .discharging:
            break
        }
    }

    /// The battery's glint, bent round the ring: the swell rolls from the end of the charge on to the target, and the
    /// end it reaches lights up.
    private func drawRingGlint(at phase: Double, center: CGPoint, color: NSColor, context: CGContext) {
        let length = Double(Self.ringLength)
        let glint = ChargingGlint.frame(at: phase, bodyWidth: length, level: level, target: chargeTarget)
        let fill = ChargingGlint.fillWidth(bodyWidth: length, level: level)
        let end = ChargingGlint.targetPosition(bodyWidth: length, target: chargeTarget)

        // The swell, as short arcs whose brightness rises and falls across it, only over the part still to charge.
        let segments = 12
        let start = glint.center - glint.width / 2
        let step = glint.width / Double(segments)
        for index in 0..<segments {
            let from = max(start + Double(index) * step, fill)
            let to = min(start + Double(index + 1) * step, end)
            guard to > from else { continue }
            let brightness = sin(.pi * (Double(index) + 0.5) / Double(segments))
            color.withAlphaComponent(0.75 * brightness * glint.strength).setStroke()
            let piece = arc(around: center, from: from, to: to)
            piece.lineCapStyle = .butt
            piece.stroke()
        }

        // The end of the sweep glows as the swell arrives: the top of the ring, or the target.
        guard glint.flash > 0 else { return }
        let glow = arc(around: center, from: max(end - 3, fill), to: min(end + (chargeTarget < 1 ? 1.5 : 0), length))
        glow.lineCapStyle = .round
        color.withAlphaComponent(0.65 * glint.flash).setStroke()
        glow.stroke()
    }

    /// An arc of the ring between two distances along it, in points, measured clockwise from the top.
    private func arc(around center: CGPoint, from start: Double, to end: Double) -> NSBezierPath {
        let degreesPerPoint = 360 / Self.ringLength
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center, radius: Self.ringRadius, startAngle: 90 - CGFloat(start) * degreesPerPoint,
            endAngle: 90 - CGFloat(end) * degreesPerPoint, clockwise: true)
        path.lineWidth = Self.ringLineWidth
        return path
    }

    // MARK: Text only

    /// Next to the text: a bolt while charging, a plug while holding the charge, in the state's colour.
    func drawStateGlyph(in size: CGSize, palette: Palette) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        palette.charge.setFill()
        switch chargeState {
        case .charging: Self.boltPath(height: 12, center: center).fill()
        case .notCharging: Self.plugPath(center: center).fill()
        case .charged, .discharging: break
        }
    }
}
