#!/usr/bin/env swift
// Draws the GitHub social preview, docs/social-preview.png (1280 × 640).
//
//   swift scripts/generate-icon.swift            # first: the preview uses docs/logo.png
//   swift scripts/generate-social-preview.swift
//
// Minimal, like an Apple product page: a soft light-grey backdrop, a slice of menu bar along the top with the app's
// battery in it, and in the middle the icon, the name and one line about what it does. Upload it in the repository's
// Settings › General › Social preview. Coordinates are Core Graphics' own: origin bottom left.

import AppKit
import CoreText

let size = CGSize(width: 1280, height: 640)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

func font(_ size: CGFloat, _ weight: NSFont.Weight, monospacedDigits: Bool = false) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    guard monospacedDigits else { return font }
    let descriptor = font.fontDescriptor.addingAttributes([
        .featureSettings: [
            [
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]
        ]
    ])
    return NSFont(descriptor: descriptor, size: size) ?? font
}

/// Draws a line of text centred on `x` (or starting at it), with its baseline at `y`. Returns its width.
@discardableResult
func text(
    _ string: String, _ font: NSFont, _ color: CGColor, x: CGFloat, y: CGFloat, centered: Bool = true,
    tracking: CGFloat = 0, in context: CGContext
) -> CGFloat {
    let attributed = NSAttributedString(
        string: string, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: tracking])
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(x: centered ? x - width / 2 : x, y: y)
    CTLineDraw(line, context)
    return width
}

/// The menu bar battery: a pill, full to `level`, with the percentage cut out, and its terminal.
func battery(at origin: CGPoint, height: CGFloat, level: CGFloat, percentage: Int, in context: CGContext) {
    let body = CGRect(origin: origin, size: CGSize(width: height * 23 / 12, height: height))
    let radius = height * 0.38
    let ink = gray(0.11)

    context.saveGState()
    context.clip(to: CGRect(x: body.maxX + height / 12, y: 0, width: height / 8, height: size.height))
    context.addEllipse(in: CGRect(x: body.maxX + height / 12 - height / 8, y: body.midY - height / 6, width: height / 4, height: height / 3))
    context.setFillColor(gray(0.11, 0.4))
    context.fillPath()
    context.restoreGState()

    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.saveGState()
    context.addPath(NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).cgPath)
    context.clip()
    context.setFillColor(gray(0.11, 0.4))
    context.fill(body)
    context.setFillColor(ink)
    context.fill(CGRect(x: body.minX, y: body.minY, width: body.width * level, height: body.height))
    context.restoreGState()
    context.setBlendMode(.destinationOut)
    let label = font(height * 0.82, .semibold, monospacedDigits: true)
    text("\(percentage)", label, gray(0), x: body.midX, y: body.midY - height * 0.29, in: context)
    context.endTransparencyLayer()
}

let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Backdrop: Apple's light grey, a touch brighter at the top.
let backdrop = CGGradient(colorsSpace: srgb, colors: [gray(0.975), gray(0.925)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(backdrop, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])

// A slice of menu bar, with the battery among the usual items on the right.
let barHeight: CGFloat = 44
context.setFillColor(gray(1, 0.75))
context.fill(CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight))
context.setFillColor(gray(0, 0.06))
context.fill(CGRect(x: 0, y: size.height - barHeight, width: size.width, height: 1))
let barText = font(19, .medium, monospacedDigits: true)
let baseline = size.height - barHeight / 2 - 7
text("Tue 10 Nov  13.24", barText, gray(0.11), x: size.width - 40 - 166, y: baseline, centered: false, in: context)
battery(at: CGPoint(x: size.width - 40 - 166 - 74, y: size.height - barHeight / 2 - 10.5), height: 21, level: 0.64, percentage: 64, in: context)

// The icon, the name, the line.
if let logo = NSImage(contentsOf: root.appending(path: "docs/logo.png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    context.interpolationQuality = .high
    context.draw(logo, in: CGRect(x: size.width / 2 - 110, y: 300, width: 220, height: 220))
}
text("WatchMyBattery", font(76, .bold), gray(0.11), x: size.width / 2, y: 200, tracking: -1.6, in: context)
text("Your battery, and who's draining it.", font(32, .regular), gray(0.43), x: size.width / 2, y: 140, tracking: -0.3, in: context)

let image = context.makeImage()!
try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    .write(to: root.appending(path: "docs/social-preview.png"))
print("Wrote docs/social-preview.png")
