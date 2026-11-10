#!/usr/bin/env swift
// Draws the WatchMyBattery app icon and logo.
//
//   swift scripts/generate-icon.swift
//
// The icon is the app's menu bar battery, full, with "100" cut out of it, on a plain tile. Nothing else.
//
// It's written as an Icon Composer icon, WatchMyBattery/AppIcon.icon: one layer (the battery) over the system's
// white fill. macOS draws the tile, its shape and shadow, and makes the dark, clear and tinted versions itself:
// black battery on white in light mode, white on dark in dark mode. docs/logo.png is a flat 1024 px rendering of the
// light version for the README. Coordinates are Core Graphics' own: origin bottom left.

import AppKit
import CoreText
import SwiftUI

let canvas = CGSize(width: 1024, height: 1024)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185.4
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

/// A rounded rectangle with Apple's continuous ("squircle") corners. macOS only shows an icon as is when its tile
/// matches this shape; anything else gets put on a grey plate.
func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: min(radius, rect.width / 2, rect.height / 2), style: .continuous).cgPath
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

// MARK: - The tile

func drawTile(in context: CGContext) {
    let shape = continuousRect(tile, radius: tileRadius)

    // Apple's template shadow: a soft, low drop.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: gray(0, 0.3))
    context.addPath(shape)
    context.setFillColor(gray(1))
    context.fillPath()
    context.restoreGState()

    // White, falling off very slightly towards the bottom.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let fill = CGGradient(colorsSpace: srgb, colors: [gray(1), gray(0.93)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(fill, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    context.restoreGState()

    // A hairline edge, so the tile holds its shape on white backgrounds.
    context.addPath(continuousRect(tile.insetBy(dx: 1, dy: 1), radius: tileRadius - 1))
    context.setStrokeColor(gray(0, 0.08))
    context.setLineWidth(2)
    context.strokePath()
}

// MARK: - The battery

/// The menu bar icon's proportions (a 23 × 12 pill, a 1.5 × 4 terminal 1 pt away), scaled up.
func drawBattery(in context: CGContext, scale: CGFloat = 25) {
    let body = CGSize(width: 23 * scale, height: 12 * scale)
    let terminal = CGSize(width: 1.5 * scale, height: 4 * scale)
    let gap = 1 * scale
    let totalWidth = body.width + gap + terminal.width
    let origin = CGPoint(x: (canvas.width - totalWidth) / 2, y: (canvas.height - body.height) / 2)
    let bodyRect = CGRect(origin: origin, size: body)
    let ink = gray(0.1)

    // The terminal: a half-round nub, the right half of an ellipse.
    let nubLeft = bodyRect.maxX + gap
    context.saveGState()
    context.clip(to: CGRect(x: nubLeft, y: 0, width: terminal.width, height: canvas.height))
    context.addEllipse(
        in: CGRect(x: nubLeft - terminal.width, y: bodyRect.midY - terminal.height / 2, width: terminal.width * 2, height: terminal.height))
    context.setFillColor(ink)
    context.fillPath()
    context.restoreGState()

    // The pill, full, with "100" cut out of it so the tile shows through.
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(continuousRect(bodyRect, radius: body.height * 0.38))
    context.setFillColor(ink)
    context.fillPath()

    let font = NSFont.systemFont(ofSize: body.height * 0.78, weight: .semibold)
    let digits = font.fontDescriptor.addingAttributes([
        .featureSettings: [
            [
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]
        ]
    ])
    let text = NSAttributedString(
        string: "100",
        attributes: [.font: NSFont(descriptor: digits, size: font.pointSize) ?? font, .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.setBlendMode(.destinationOut)
    context.textPosition = CGPoint(x: bodyRect.midX - bounds.midX, y: bodyRect.midY - bounds.midY)
    CTLineDraw(line, context)
    context.endTransparencyLayer()
}

// MARK: - Output

func render(_ paint: (CGContext) -> Void) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldSmoothFonts(false)
    paint(context)
    return context.makeImage()!
}

func pngData(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconFile = root.appending(path: "WatchMyBattery/AppIcon.icon")
try FileManager.default.createDirectory(at: iconFile.appending(path: "Assets"), withIntermediateDirectories: true)

// The layer: the battery alone on a transparent 1024 canvas, sized for Icon Composer's full-bleed tile.
// Its colour comes from icon.json, per appearance.
try pngData(render { drawBattery(in: $0, scale: 30) }).write(to: iconFile.appending(path: "Assets/battery.png"))

let manifest = """
    {
      "fill" : {
        "automatic-gradient" : "srgb:1.00000,1.00000,1.00000,1.00000"
      },
      "groups" : [
        {
          "layers" : [
            {
              "fill-specializations" : [
                { "value" : { "solid" : "srgb:0.11000,0.11000,0.11500,1.00000" } },
                { "appearance" : "dark", "value" : { "solid" : "srgb:1.00000,1.00000,1.00000,1.00000" } }
              ],
              "glass" : false,
              "image-name" : "battery.png",
              "name" : "battery"
            }
          ],
          "shadow" : {
            "kind" : "neutral",
            "opacity" : 0.25
          },
          "translucency" : {
            "enabled" : false,
            "value" : 0.5
          }
        }
      ],
      "supported-platforms" : {
        "squares" : [
          "macOS"
        ]
      }
    }

    """
try manifest.write(to: iconFile.appending(path: "icon.json"), atomically: true, encoding: .utf8)

// The README logo: the light version, flat.
let logo = render { context in
    drawTile(in: context)
    drawBattery(in: context)
}
try pngData(logo).write(to: root.appending(path: "docs/logo.png"))
print("Wrote WatchMyBattery/AppIcon.icon and docs/logo.png")
