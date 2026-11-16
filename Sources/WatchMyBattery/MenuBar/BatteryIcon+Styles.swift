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
            // Copied over the track, so the charge's own brightness shows: it breathes while it's held.
            context.saveGState()
            context.setBlendMode(.copy)
            palette.charge.withAlphaComponent(chargeOpacity).setStroke()
            if level >= 1 {
                track.stroke()
            } else {
                // As long as the battery's fill would be (so the glint starts where it ends), with the round caps
                // inside that length, so a nearly full ring still shows its gap.
                let length = ChargingGlint.fillWidth(bodyWidth: Double(Self.ringLength), level: level) + liquidLean
                let cap = Double(Self.ringLineWidth) / 2
                let charge = arc(around: center, from: cap, to: max(length - cap, cap + 0.01))
                charge.lineCapStyle = .round
                charge.stroke()
            }
            context.restoreGState()
        }

        if let motion, let animationPhase {
            switch motion {
            case .flow: drawRingGlint(at: animationPhase, center: center, color: palette.charge, context: context)
            case .stripes: drawRingStripes(at: animationPhase, center: center, color: palette.charge, context: context)
            case .slowPulse: drawRingEdgeGlow(strength: EdgePulse.strength(at: animationPhase), center: center, color: palette.charge)
            case .liquid, .calmLiquid, .stillWater, .heartbeat, .breathing: break  // In the charge's length, brightness or the glyph.
            }
        }

        let glyph = glyphTransform(around: center)
        switch chargeState {
        case .charging:
            palette.charge.setFill()
            let bolt = Self.boltPath(height: 8, center: center)
            bolt.transform(using: glyph)
            bolt.fill()
        case .notCharging:
            palette.charge.withAlphaComponent(chargeOpacity).setFill()
            let plug = Self.plugPath(center: .zero)
            var transform = AffineTransform(translationByX: center.x, byY: center.y)
            transform.scale(0.75)
            plug.transform(using: transform)
            plug.transform(using: glyph)
            plug.fill()
        case .charged, .discharging:
            break
        }
    }

    /// A liquid's surface, round the ring: the end of the charge sways a little forward and back, as the battery's edge
    /// ripples. In points along the ring.
    private var liquidLean: Double {
        guard let motion, let phase = animationPhase else { return 0 }
        let middle = Double(Self.ringLineWidth) / 2
        switch motion {
        case .liquid: return 1.4 * LiquidSurface.charging(y: middle * 3, phase: phase)
        case .calmLiquid: return 1.4 * LiquidSurface.calm(y: middle * 3, phase: phase)
        case .stillWater: return 1.6 * sin(2 * .pi * phase)
        default: return 0
        }
    }

    /// The battery's stripes, round the ring: short dashes gliding along the part still to charge.
    private func drawRingStripes(at phase: Double, center: CGPoint, color: NSColor, context: CGContext) {
        let length = Double(Self.ringLength)
        let start = ChargingGlint.fillWidth(bodyWidth: length, level: level)
        let end = ChargingGlint.targetPosition(bodyWidth: length, target: chargeTarget)
        guard end > start else { return }
        color.withAlphaComponent(motionPeak * 0.8).setStroke()
        var from = start - Stripes.spacing + Stripes.offset(at: phase)
        while from < end {
            let piece = arc(around: center, from: max(from, start), to: min(from + Stripes.spacing / 2, end))
            piece.lineCapStyle = .butt
            if from + Stripes.spacing / 2 > start { piece.stroke() }
            from += Stripes.spacing
        }
    }

    /// A soft glow at the end of the ring's charge, `strength` 0–1.
    private func drawRingEdgeGlow(strength: Double, center: CGPoint, color: NSColor) {
        guard strength > 0.01 else { return }
        let end = ChargingGlint.fillWidth(bodyWidth: Double(Self.ringLength), level: level)
        let reach = 2.5 + 1.5 * strength
        let segments = 8
        for index in 0..<segments {
            let from = end - reach + 2 * reach * Double(index) / Double(segments)
            let to = from + 2 * reach / Double(segments)
            color.withAlphaComponent(0.8 * sin(.pi * (Double(index) + 0.5) / Double(segments)) * strength).setStroke()
            let piece = arc(around: center, from: from, to: to)
            piece.lineCapStyle = .butt
            piece.stroke()
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
            color.withAlphaComponent(motionPeak * brightness * glint.strength).setStroke()
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
