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
            palette.charge.setStroke()
            if level >= 1 {
                track.stroke()
            } else {
                // As long as the battery's fill would be (so the glint starts where it ends), with the round caps
                // inside that length, so a nearly full ring still shows its gap.
                let length = ChargingGlint.fillWidth(bodyWidth: Double(Self.ringLength), level: level)
                let cap = Double(Self.ringLineWidth) / 2
                let charge = arc(around: center, from: cap, to: max(length - cap, cap + 0.01))
                charge.lineCapStyle = .round
                charge.stroke()
            }
        }

        if let animationPhase {
            switch chargeState {
            case .charging: drawRingGlint(at: animationPhase, center: center, color: palette.charge, context: context)
            case .notCharging: drawRingShimmer(at: animationPhase, center: center, color: palette.charge, context: context)
            case .charged, .discharging: break
            }
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

    /// Holding its charge: the battery's shimmer, bent round the ring. A sheen glides along the charge from the top,
    /// cut out of it, and the end of the charge glows as it arrives.
    private func drawRingShimmer(at phase: Double, center: CGPoint, color: NSColor, context: CGContext) {
        let fill = ChargingGlint.fillWidth(bodyWidth: Double(Self.ringLength), level: level)
        let frame = RestingShimmer.frame(at: phase, fillWidth: fill)

        if frame.strength > 0.01 {
            context.saveGState()
            context.setBlendMode(.destinationOut)
            let segments = 10
            let start = frame.center - frame.width / 2
            let step = frame.width / Double(segments)
            for index in 0..<segments {
                let from = max(start + Double(index) * step, 0)
                let to = min(start + Double(index + 1) * step, fill)
                guard to > from else { continue }
                let brightness = sin(.pi * (Double(index) + 0.5) / Double(segments))
                NSColor.black.withAlphaComponent(0.6 * brightness * frame.strength).setStroke()
                let piece = arc(around: center, from: from, to: to)
                piece.lineCapStyle = .butt
                piece.stroke()
            }
            context.restoreGState()
        }

        guard frame.glow > 0.01 else { return }
        let reach = 2.5 + 3 * frame.glow
        let segments = 8
        for index in 0..<segments {
            let from = fill - reach + 2 * reach * Double(index) / Double(segments)
            let to = from + 2 * reach / Double(segments)
            let brightness = sin(.pi * (Double(index) + 0.5) / Double(segments))
            color.withAlphaComponent(0.8 * brightness * frame.glow).setStroke()
            let piece = arc(around: center, from: from, to: to)
            piece.lineCapStyle = .butt
            piece.stroke()
        }
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
