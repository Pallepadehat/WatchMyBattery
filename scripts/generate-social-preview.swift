#!/usr/bin/env swift  // Draws the GitHub social preview, docs/social-preview.png (1280 × 640).
//
//   swift scripts/generate-icon.swift            # first: the preview uses docs/logo.png
//   swift scripts/generate-social-preview.swift
//
// A dark, keynote-style card: a faint aurora over a deep gradient, a Mac menu bar along the top with the app's pill
// battery in it, and the app's panel hanging from it, one slice being dragged out to quit its app. On the left, the
// icon, the name and a one-line pitch. Everything except the icon is drawn here, in layers, with Core Graphics and
// Core Text. Coordinates are Core Graphics' own: origin bottom left.

import AppKit
import CoreImage
import CoreText
import SwiftUI

let size = CGSize(width: 1280, height: 640)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - Helpers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// A gradient from (colour, alpha, location) stops.
func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map(\.2))!
}

/// A rounded rectangle with Apple's continuous corners.
func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: min(radius, rect.width / 2, rect.height / 2), style: .continuous).cgPath
}

/// A rectangle rounded on its right side only, like a battery's terminal or the end of its fill.
func rightRounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let shape = UnevenRoundedRectangle(
        cornerRadii: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: radius, topTrailing: radius), style: .continuous)
    return shape.path(in: rect).cgPath
}

func bitmap(_ size: CGSize) -> CGContext {
    let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    return context
}

/// Paints into a fresh transparent card-sized layer, so it can be blurred or blended.
func layer(_ paint: (CGContext) -> Void) -> CGImage {
    let context = bitmap(size)
    paint(context)
    return context.makeImage()!
}

func blurred(_ image: CGImage, _ radius: CGFloat) -> CGImage {
    let input = CIImage(cgImage: image)
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    return ciContext.createCGImage(output, from: input.extent)!
}

func composite(_ image: CGImage, in context: CGContext, blend: CGBlendMode = .normal, alpha: CGFloat = 1) {
    context.saveGState()
    context.setBlendMode(blend)
    context.setAlpha(alpha)
    context.draw(image, in: CGRect(origin: .zero, size: size))
    context.restoreGState()
}

func radialGlow(_ hex: UInt32, _ alpha: CGFloat, at center: CGPoint, radius: CGFloat, in context: CGContext) {
    let glow = gradient([(hex, alpha, 0), (hex, alpha * 0.45, 0.4), (hex, 0, 1)])
    context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func verticalGradient(_ gradient: CGGradient, in context: CGContext, top: CGFloat, bottom: CGFloat) {
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
}

/// Fine monochrome grain, so the dark gradients don't band.
func grain() -> CGImage {
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
    let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    return ciContext.createCGImage(mono, from: CGRect(origin: .zero, size: size))!
}

/// A line of text in the system font (SF Pro), with tracking in points.
func line(_ text: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0, rounded: Bool = false, color fill: CGColor) -> CTLine {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
        font = NSFont(descriptor: descriptor, size: size)!
    }
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking, .foregroundColor: fill]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
}

func width(of line: CTLine) -> CGFloat {
    CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

func draw(_ line: CTLine, at point: CGPoint, in context: CGContext) {
    context.textPosition = point
    CTLineDraw(line, context)
}

/// Draws an SF Symbol, tinted, centred on `center`, and returns its frame.
@discardableResult
func drawSymbol(
    _ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, tint: CGColor, center: CGPoint, in context: CGContext
) -> CGRect {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
    let scale: CGFloat = 3
    let symbol = bitmap(CGSize(width: image.size.width * scale, height: image.size.height * scale))
    symbol.scaleBy(x: scale, y: scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: symbol, flipped: false)
    image.draw(in: CGRect(origin: .zero, size: image.size))
    NSGraphicsContext.current = nil
    symbol.setBlendMode(.sourceIn)
    symbol.setFillColor(tint)
    symbol.fill(CGRect(origin: .zero, size: image.size))
    let frame = CGRect(
        x: center.x - image.size.width / 2, y: center.y - image.size.height / 2, width: image.size.width, height: image.size.height)
    context.draw(symbol.makeImage()!, in: frame)
    return frame
}

// MARK: - Background

func drawBackground(in context: CGContext) {
    // A deep midnight gradient, a little lighter at the top.
    verticalGradient(gradient([(0x15183F, 1, 0), (0x0B0C26, 1, 0.55), (0x060616, 1, 1)]), in: context, top: size.height, bottom: 0)

    // Aurora: soft indigo, violet and teal light, blurred so no shape survives, only colour.
    let aurora = layer { layer in
        radialGlow(0x3D4BD8, 0.55, at: CGPoint(x: 260, y: 360), radius: 440, in: layer)
        radialGlow(0x7B3FD6, 0.38, at: CGPoint(x: 1060, y: 560), radius: 440, in: layer)
        radialGlow(0x1E9BC8, 0.20, at: CGPoint(x: 900, y: 40), radius: 360, in: layer)
    }
    composite(blurred(aurora, 30), in: context, blend: .screen)

    // A vignette pulling the corners down, and grain to hide banding.
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    context.drawRadialGradient(
        gradient([(0x000000, 0, 0.55), (0x000000, 0.45, 1)]), startCenter: center, startRadius: 0, endCenter: center,
        endRadius: size.width * 0.62, options: [.drawsAfterEndLocation])
    composite(grain(), in: context, blend: .overlay, alpha: 0.06)
}

// MARK: - The menu bar

/// The app's menu bar battery: a solid pill, bright up to the charge and translucent beyond, with a tiny nub.
func drawPillBattery(in context: CGContext, rect: CGRect, charge: CGFloat) {
    context.saveGState()
    context.addPath(continuousRect(rect, radius: rect.height * 0.36))
    context.clip()
    context.setFillColor(color(0xFFFFFF, 0.38))
    context.fill(rect)
    context.setFillColor(color(0xFFFFFF))
    context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * charge, height: rect.height))
    context.restoreGState()

    let nub = CGRect(x: rect.maxX + 1.5, y: rect.midY - rect.height * 0.2, width: rect.height * 0.2, height: rect.height * 0.4)
    context.addPath(rightRounded(nub, radius: nub.width))
    context.setFillColor(color(0xFFFFFF, 0.38))
    context.fillPath()
}

/// Draws the menu bar and returns the frame of the battery item, which the panel hangs from.
func drawMenuBar(in context: CGContext) -> CGRect {
    let bar = CGRect(x: 0, y: size.height - 34, width: size.width, height: 34)

    // A translucent strip with a hairline beneath it.
    context.setFillColor(color(0xFFFFFF, 0.06))
    context.fill(bar)
    context.setFillColor(color(0xFFFFFF, 0.08))
    context.fill(CGRect(x: 0, y: bar.minY, width: size.width, height: 1))

    // Status items, right to left: the clock, Control Centre, Spotlight, Wi-Fi, then the battery.
    let ink = color(0xFFFFFF, 0.92)
    let clock = line("Tue 10 Nov  9:41", size: 15, weight: .medium, color: ink)
    var x = size.width - 40 - width(of: clock)
    draw(clock, at: CGPoint(x: x, y: bar.minY + 11), in: context)
    for name in ["switch.2", "magnifyingglass", "wifi"] {
        let frame = drawSymbol(name, pointSize: 15, weight: .medium, tint: ink, center: CGPoint(x: x - 36, y: bar.midY), in: context)
        x = frame.minX
    }

    // The battery, with the soft highlight of an open menu behind it.
    let battery = CGRect(x: x - 26 - 30, y: bar.midY - 6.5, width: 30, height: 13)
    let highlight = continuousRect(battery.insetBy(dx: -11, dy: -6.5).offsetBy(dx: 1, dy: 0), radius: 7)
    context.addPath(highlight)
    context.setFillColor(color(0xFFFFFF, 0.16))
    context.fillPath()
    drawPillBattery(in: context, rect: battery, charge: 0.72)
    return highlight.boundingBox
}

// MARK: - The panel

/// An app in the panel: its slice colours, its icon's glyph, its slice width (in panel points), and the time it costs.
struct App {
    let name: String
    let top: UInt32
    let bottom: UInt32
    let glyph: String
    let width: CGFloat
    let cost: String
}

let apps = [
    App(name: "Video Editor", top: 0xFF6990, bottom: 0xE42A5C, glyph: "film.fill", width: 46, cost: "\u{2212}1:12"),
    App(name: "Browser", top: 0xFFA35C, bottom: 0xF06A22, glyph: "safari.fill", width: 36, cost: "\u{2212}38m"),
    App(name: "Game", top: 0xFFDB6E, bottom: 0xF4AA20, glyph: "gamecontroller.fill", width: 30, cost: "\u{2212}24m"),
]

/// The panel is drawn in the app's own points (it's 320 pt wide) and scaled up to suit the card.
let panelScale: CGFloat = 1.6
let panelSize = CGSize(width: 320, height: 245)

/// A stand-in app icon: a light tile with the app's glyph in its colour.
func drawAppIcon(_ app: App, in rect: CGRect, context: CGContext) {
    let radius = rect.width * 0.225
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.05), blur: rect.width * 0.12, color: color(0x000000, 0.3))
    context.addPath(continuousRect(rect, radius: radius))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(continuousRect(rect, radius: radius))
    context.clip()
    verticalGradient(gradient([(0xFFFFFF, 1, 0), (0xE9ECF4, 1, 1)]), in: context, top: rect.maxY, bottom: rect.minY)
    context.restoreGState()
    drawSymbol(
        app.glyph, pointSize: rect.width * 0.5, weight: .semibold, tint: color(app.bottom), center: CGPoint(x: rect.midX, y: rect.midY),
        in: context)
}

/// The panel's contents, laid out top-down like BatteryPanelView, in a context already scaled to panel points.
func drawPanelContents(in context: CGContext) {
    let panelWidth = panelSize.width
    let top = panelSize.height
    let inset: CGFloat = 16
    let primary = color(0xFFFFFF, 0.92)
    let secondary = color(0xEBEBF5, 0.58)

    // Header: "Battery" and the percentage, then the power source.
    let title = line("Battery", size: 13, weight: .bold, color: primary)
    draw(title, at: CGPoint(x: inset, y: top - 26), in: context)
    draw(line("72%", size: 13, weight: .regular, color: secondary), at: CGPoint(x: inset + width(of: title) + 6, y: top - 26), in: context)
    draw(line("Power Source: Battery", size: 12, weight: .regular, color: secondary), at: CGPoint(x: inset, y: top - 42), in: context)

    // The gauge: a faint capsule track, its outline and the terminal.
    let capsule = CGRect(x: inset, y: top - 132, width: panelWidth - inset * 2 - 8, height: 72)
    let capsulePath = continuousRect(capsule, radius: capsule.height / 2)
    context.addPath(capsulePath)
    context.setFillColor(color(0xFFFFFF, 0.08))
    context.fillPath()
    context.addPath(rightRounded(CGRect(x: capsule.maxX + 3, y: capsule.midY - 13, width: 5, height: 26), radius: 3))
    context.setFillColor(color(0xFFFFFF, 0.2))
    context.fillPath()

    // The fill: white charge up to 72%, ending in the apps' slices. The last one is being dragged out, so it's faded
    // and its icon has gone with the pointer.
    let fillWidth = capsule.width * 0.72
    let baseWidth = fillWidth - apps.reduce(0) { $0 + $1.width }
    let slices = apps.reduce(into: [CGRect]()) { rects, app in
        let x = rects.last?.maxX ?? capsule.minX + baseWidth
        rects.append(CGRect(x: x, y: capsule.minY, width: app.width, height: capsule.height))
    }
    context.saveGState()
    context.addPath(capsulePath)
    context.clip()
    let fillPath = rightRounded(CGRect(x: capsule.minX, y: capsule.minY, width: fillWidth, height: capsule.height), radius: 8)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 1, height: 0), blur: 3, color: color(0x000000, 0.18))
    context.addPath(fillPath)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
    context.addPath(fillPath)
    context.clip()
    for (index, (app, rect)) in zip(apps, slices).enumerated() {
        let dragged = index == apps.count - 1
        context.saveGState()
        context.clip(to: rect)
        context.setAlpha(dragged ? 0.35 : 1)
        verticalGradient(gradient([(app.top, 1, 0), (app.bottom, 1, 1)]), in: context, top: rect.maxY, bottom: rect.minY)
        context.restoreGState()
        context.setFillColor(color(0x000000, 0.18))
        context.fill(CGRect(x: rect.minX, y: rect.minY, width: 0.75, height: rect.height))
        if !dragged {
            drawAppIcon(app, in: CGRect(x: rect.midX - 11, y: rect.midY - 11, width: 22, height: 22), context: context)
        }
    }
    context.restoreGState()
    context.addPath(continuousRect(capsule.insetBy(dx: 0.5, dy: 0.5), radius: capsule.height / 2))
    context.setStrokeColor(color(0xFFFFFF, 0.14))
    context.setLineWidth(1)
    context.strokePath()

    let time = line("4:50", size: 21, weight: .semibold, rounded: true, color: color(0x000000, 0.85))
    draw(time, at: CGPoint(x: capsule.minX + (baseWidth - width(of: time)) / 2 + 4, y: capsule.midY - 7.5), in: context)

    // What each app costs, under its slice.
    for (app, rect) in zip(apps, slices).dropLast() {
        let cost = line(app.cost, size: 10.5, weight: .medium, color: secondary)
        draw(cost, at: CGPoint(x: rect.midX - width(of: cost) / 2, y: capsule.minY - 14), in: context)
    }

    // The time row previews quitting the app being dragged.
    let rowY = top - 172
    draw(line("Without Game", size: 13, weight: .regular, color: secondary), at: CGPoint(x: inset, y: rowY), in: context)
    let gain = line("+24m", size: 13, weight: .semibold, color: color(0x32D74B))
    let gainX = panelWidth - inset - width(of: gain)
    draw(gain, at: CGPoint(x: gainX, y: rowY), in: context)
    let left = line("4:50", size: 13, weight: .regular, color: primary)
    draw(left, at: CGPoint(x: gainX - 6 - width(of: left), y: rowY), in: context)

    // A divider and the two menu rows.
    context.setFillColor(color(0xFFFFFF, 0.12))
    context.fill(CGRect(x: inset, y: top - 187, width: panelWidth - inset * 2, height: 0.75))
    draw(line("Battery Settings…", size: 13, weight: .regular, color: primary), at: CGPoint(x: inset, y: top - 210), in: context)
    draw(line("WatchMyBattery Settings…", size: 13, weight: .regular, color: primary), at: CGPoint(x: inset, y: top - 233), in: context)
}

/// The app's panel, hanging from the menu bar, and the slice being dragged out of it: the app's icon following the
/// pointer, armed to quit. Returns the panel's frame.
@discardableResult
func drawPanel(below item: CGRect, in context: CGContext) -> CGRect {
    let frame = CGRect(
        x: size.width - 40 - panelSize.width * panelScale, y: item.minY - 6 - panelSize.height * panelScale,
        width: panelSize.width * panelScale, height: panelSize.height * panelScale)
    let shape = continuousRect(frame, radius: 15 * panelScale)

    // Dark frosted glass with a deep, soft shadow, a sheen along the top and a fine light border.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: color(0x000000, 0.6))
    context.addPath(shape)
    context.setFillColor(color(0x1E1F38, 0.86))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    verticalGradient(gradient([(0xFFFFFF, 0.07, 0), (0xFFFFFF, 0.02, 0.4), (0xFFFFFF, 0, 1)]), in: context, top: frame.maxY, bottom: frame.minY)
    context.restoreGState()
    context.addPath(continuousRect(frame.insetBy(dx: 0.5, dy: 0.5), radius: 15 * panelScale - 0.5))
    context.setStrokeColor(color(0xFFFFFF, 0.16))
    context.setLineWidth(1)
    context.strokePath()

    context.saveGState()
    context.translateBy(x: frame.minX, y: frame.minY)
    context.scaleBy(x: panelScale, y: panelScale)
    drawPanelContents(in: context)
    context.restoreGState()

    // The dragged app, out past the panel's edge: its icon, slightly shrunk and faded as it is when armed, with the
    // red "Quit Game" label under it.
    let center = CGPoint(x: frame.minX + 205 * panelScale, y: frame.minY - 64)
    let iconSide = 52 * 0.92 * panelScale
    context.saveGState()
    context.setAlpha(0.92)
    drawAppIcon(apps.last!, in: CGRect(x: center.x - iconSide / 2, y: center.y - iconSide / 2, width: iconSide, height: iconSide), context: context)
    context.restoreGState()
    let label = line("Quit Game", size: 11 * panelScale, weight: .semibold, color: color(0xFFFFFF))
    let pill = CGRect(
        x: center.x - width(of: label) / 2 - 9 * panelScale, y: center.y - 46 * panelScale - 9 * panelScale, width: width(of: label) + 18 * panelScale,
        height: 18 * panelScale)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -2 * panelScale), blur: 4 * panelScale, color: color(0x000000, 0.25))
    context.addPath(continuousRect(pill, radius: pill.height / 2))
    context.clip()
    verticalGradient(gradient([(0xFF5A50, 1, 0), (0xE5352B, 1, 1)]), in: context, top: pill.maxY, bottom: pill.minY)
    context.restoreGState()
    draw(label, at: CGPoint(x: pill.minX + 9 * panelScale, y: pill.minY + 5.6 * panelScale), in: context)
    return frame
}

// MARK: - The card

func drawCard(in context: CGContext) {
    drawBackground(in: context)
    let batteryItem = drawMenuBar(in: context)

    // The icon, with a halo of its own indigo light behind it.
    let iconCanvas = CGRect(x: 58, y: 262, width: 250, height: 250)
    let halo = layer { layer in
        radialGlow(0x5865FF, 0.45, at: CGPoint(x: iconCanvas.midX, y: iconCanvas.midY), radius: 200, in: layer)
    }
    composite(halo, in: context, blend: .screen)
    let logo = NSImage(contentsOf: root.appending(path: "docs/logo.png"))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    context.draw(logo, in: iconCanvas)

    // The name, in white that cools slightly towards its baseline, and the pitch, left-aligned under the icon.
    let textX: CGFloat = 80
    let name = layer { layer in
        draw(line("WatchMyBattery", size: 68, weight: .bold, tracking: -1.8, color: color(0xFFFFFF)), at: CGPoint(x: textX, y: 196), in: layer)
        layer.setBlendMode(.sourceIn)
        verticalGradient(gradient([(0xFFFFFF, 1, 0), (0xFFFFFF, 1, 0.35), (0xC9CFF2, 1, 1)]), in: layer, top: 248, bottom: 180)
    }
    composite(name, in: context)
    let secondary = color(0xC3C8E6, 0.78)
    draw(
        line("Your battery, and who’s draining it.", size: 27, weight: .regular, tracking: -0.3, color: secondary), at: CGPoint(x: textX + 3, y: 148),
        in: context)
    draw(line("Right in the menu bar.", size: 27, weight: .regular, tracking: -0.3, color: secondary), at: CGPoint(x: textX + 3, y: 113), in: context)

    drawPanel(below: batteryItem, in: context)
}

let context = bitmap(size)
drawCard(in: context)
let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: root.appending(path: "docs/social-preview.png"))
print("Social preview written to docs/social-preview.png")
