#!/usr/bin/env swift
// Draws the WatchMyBattery app icon and logo.
//
//   swift scripts/generate-icon.swift
//
// Writes every size the asset catalog needs, plus docs/logo.png (1024 px). The artwork follows Apple's macOS icon
// grid: an 824 × 824 pt squircle centred on a 1024 × 1024 pt canvas, with a soft drop shadow. On it sits a glossy
// white battery whose fill ends in three coloured app slices, like the app's panel.

import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map { color($0.0, $0.1) } as CFArray,
        locations: stops.map(\.2)
    )!
}

/// A superellipse (|x|^n + |y|^n = 1), the continuous-curvature "squircle" macOS icons use, rather than a rounded
/// rectangle with circular corners. Sampled finely enough to be smooth at 1024 px.
func squircle(in rect: CGRect, exponent: CGFloat = 4.2) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(angle)
        let s = sin(angle)
        let x = pow(abs(c), 2 / exponent) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / exponent) * (s < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    let r = min(radius, rect.height / 2, rect.width / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Draws the icon into a 1024 × 1024 context with a top-left origin.
func drawIcon(in context: CGContext) {
    let shape = squircle(in: body)

    // Drop shadow under the whole tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x000000, 0.4))
    context.addPath(shape)
    context.setFillColor(color(0x141A5C))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    // A deep blue to indigo sky, like the macOS wallpaper, lit from the top left.
    let sky = gradient([(0x2F5BEA, 1, 0), (0x2234B8, 1, 0.38), (0x1B1F7E, 1, 0.72), (0x150F4D, 1, 1)])
    context.drawLinearGradient(sky, start: CGPoint(x: 220, y: 100), end: CGPoint(x: 800, y: 924), options: [])

    // Soft light: a cyan bloom top left, a violet one bottom right.
    let cyanBloom = gradient([(0x5FC4FF, 0.42, 0), (0x5FC4FF, 0, 1)])
    context.drawRadialGradient(
        cyanBloom, startCenter: CGPoint(x: 230, y: 180), startRadius: 0, endCenter: CGPoint(x: 230, y: 180), endRadius: 520,
        options: [])
    let violetBloom = gradient([(0x9B4FE8, 0.6, 0), (0x9B4FE8, 0, 1)])
    context.drawRadialGradient(
        violetBloom, startCenter: CGPoint(x: 860, y: 900), startRadius: 0, endCenter: CGPoint(x: 860, y: 900), endRadius: 560,
        options: [])

    // A soft glow behind the battery, so it lifts off the tile.
    let halo = gradient([(0x8FA8FF, 0.35, 0), (0x8FA8FF, 0, 1)])
    context.drawRadialGradient(
        halo, startCenter: CGPoint(x: 512, y: 520), startRadius: 0, endCenter: CGPoint(x: 512, y: 520), endRadius: 380,
        options: [])

    drawBattery(in: context)

    // A glassy sheen over the top of the tile, and a gentle highlight along its edge.
    let sheen = gradient([(0xFFFFFF, 0.14, 0), (0xFFFFFF, 0, 1)])
    context.drawLinearGradient(sheen, start: CGPoint(x: 512, y: body.minY), end: CGPoint(x: 512, y: 470), options: [])
    context.restoreGState()

    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.16))
    context.setLineWidth(4)
    context.strokePath()
}

/// The battery: a white capsule with a terminal nub, its fill white up to the charge level and then three app slices.
func drawBattery(in context: CGContext) {
    let outer = CGRect(x: 196, y: 376, width: 566, height: 272)
    let nub = CGRect(x: outer.maxX + 18, y: outer.midY - 56, width: 46, height: 112)
    let outerRadius: CGFloat = 104
    let rim: CGFloat = 22
    let inner = outer.insetBy(dx: rim, dy: rim)
    let fillArea = inner.insetBy(dx: 14, dy: 14)
    let fillRadius = outerRadius - rim - 14

    // Shadow under the battery, so it floats above the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 22), blur: 44, color: color(0x060828, 0.55))
    context.addPath(roundedRect(outer, outerRadius))
    context.addPath(roundedRect(nub, 22))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    // The white casing, with a cool gradient so it reads as glossy rather than flat.
    let casing = gradient([(0xFFFFFF, 1, 0), (0xF1F4FC, 1, 0.55), (0xD3DAF1, 1, 1)])
    for (rect, radius) in [(outer, outerRadius), (nub, 22)] {
        context.saveGState()
        context.addPath(roundedRect(rect, radius))
        context.clip()
        context.drawLinearGradient(casing, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        context.restoreGState()
    }

    // The dark glass inside the casing.
    context.saveGState()
    context.addPath(roundedRect(inner, outerRadius - rim))
    context.clip()
    let glass = gradient([(0x0E1452, 1, 0), (0x232A80, 1, 1)])
    context.drawLinearGradient(glass, start: CGPoint(x: 0, y: inner.minY), end: CGPoint(x: 0, y: inner.maxY), options: [])
    // An inner shadow along the top edge of the glass.
    let innerShadow = gradient([(0x000000, 0.35, 0), (0x000000, 0, 1)])
    context.drawLinearGradient(
        innerShadow, start: CGPoint(x: 0, y: inner.minY), end: CGPoint(x: 0, y: inner.minY + 40), options: [])
    context.restoreGState()

    // The fill: white charge, then the apps using the most energy, then what's already gone.
    context.saveGState()
    context.addPath(roundedRect(fillArea, fillRadius))
    context.clip()

    let charge = fillArea.width * 0.47
    let slices: [(UInt32, UInt32, CGFloat)] = [
        (0xB97AF0, 0xA35BE0, 0.135),  // purple
        (0x5BB3F0, 0x3A9BE0, 0.115),  // blue
        (0xEA5F88, 0xD9406E, 0.10),  // pink
    ]
    let gap: CGFloat = 8

    let white = gradient([(0xFFFFFF, 1, 0), (0xEEF1FA, 1, 1)])
    context.saveGState()
    context.clip(to: CGRect(x: fillArea.minX, y: fillArea.minY, width: charge, height: fillArea.height))
    context.drawLinearGradient(
        white, start: CGPoint(x: 0, y: fillArea.minY), end: CGPoint(x: 0, y: fillArea.maxY), options: [])
    context.restoreGState()

    var x = fillArea.minX + charge + gap
    for (light, deep, fraction) in slices {
        let width = fillArea.width * fraction - gap
        let rect = CGRect(x: x, y: fillArea.minY, width: width, height: fillArea.height)
        context.saveGState()
        context.clip(to: rect)
        let slice = gradient([(light, 1, 0), (deep, 1, 1)])
        context.drawLinearGradient(slice, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        context.restoreGState()
        x += width + gap
    }

    // Gloss over the top of the fill, fading out softly (no hard edge).
    let gloss = gradient([(0xFFFFFF, 0.42, 0), (0xFFFFFF, 0.12, 0.42), (0xFFFFFF, 0, 0.62)])
    let filled = CGRect(x: fillArea.minX, y: fillArea.minY, width: x - fillArea.minX - gap, height: fillArea.height)
    context.clip(to: filled)
    context.drawLinearGradient(gloss, start: CGPoint(x: 0, y: filled.minY), end: CGPoint(x: 0, y: filled.maxY), options: [])
    context.restoreGState()

    // A bright highlight along the top of the casing.
    context.saveGState()
    context.addPath(roundedRect(outer.insetBy(dx: 3, dy: 3), outerRadius - 3))
    context.setStrokeColor(color(0xFFFFFF, 0.9))
    context.setLineWidth(3)
    context.clip(to: CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: 60))
    context.strokePath()
    context.restoreGState()
}

func render(pixels: Int) -> Data {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / canvas
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    context.interpolationQuality = .high
    drawIcon(in: context)
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "WatchMyBattery/Assets.xcassets/AppIcon.appiconset")

// (point size, scale) pairs required for a macOS app icon.
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(pixels: points * scale).write(to: iconSet.appending(path: name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appending(path: "Contents.json"))

let docs = root.appending(path: "docs")
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
try render(pixels: 1024).write(to: docs.appending(path: "logo.png"))
print("Icon written to \(iconSet.path) and docs/logo.png")
