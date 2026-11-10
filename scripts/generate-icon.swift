#!/usr/bin/env swift  // Draws the WatchMyBattery app icon and logo.
//
//   swift scripts/generate-icon.swift
//
// Writes every size the asset catalog needs, plus docs/logo.png (1024 px). The artwork follows Apple's macOS icon
// grid: an 824 × 824 pt continuous-corner tile centred on a 1024 × 1024 pt canvas, with a soft drop shadow. On it
// floats a glass battery in the macOS 26 style: a solid pill and a small terminal nub, lit where it's charged, with
// the apps draining it as coloured slices at the end of the charge, like the app's panel.
//
// The icon is painted once at 1024 px from layers (gradients, Core Image blurs, clipping and blend modes) and then
// downsampled with a Lanczos filter for the smaller sizes. Coordinates are Core Graphics' own: origin bottom left.

import AppKit
import CoreImage
import SwiftUI

let canvas = CGSize(width: 1024, height: 1024)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185.4
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])

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

/// A rounded rectangle with Apple's continuous ("squircle") corners, the shape of macOS icons and controls.
func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: min(radius, rect.width / 2, rect.height / 2), style: .continuous).cgPath
}

/// Paints into a fresh transparent canvas-sized bitmap and returns it, so it can be blurred or blended as a layer.
func layer(_ size: CGSize = canvas, _ paint: (CGContext) -> Void) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    paint(context)
    return context.makeImage()!
}

/// A Gaussian blur that keeps the layer's size.
func blurred(_ image: CGImage, _ radius: CGFloat) -> CGImage {
    let input = CIImage(cgImage: image)
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    return ciContext.createCGImage(output, from: input.extent)!
}

/// Draws a layer over the whole canvas with a blend mode and opacity.
func composite(_ image: CGImage, in context: CGContext, blend: CGBlendMode = .normal, alpha: CGFloat = 1) {
    context.saveGState()
    context.setBlendMode(blend)
    context.setAlpha(alpha)
    context.draw(image, in: CGRect(origin: .zero, size: canvas))
    context.restoreGState()
}

/// Fills `rect` with a vertical gradient, from `top` down to `bottom`, inside the current clip.
func verticalGradient(_ gradient: CGGradient, in context: CGContext, top: CGFloat, bottom: CGFloat) {
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radialGlow(_ gradient: CGGradient, in context: CGContext, at center: CGPoint, radius: CGFloat) {
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Strokes `path` with a vertical gradient, which is how the glass rims catch the light from above.
func gradientStroke(_ path: CGPath, width: CGFloat, _ gradient: CGGradient, in context: CGContext, top: CGFloat, bottom: CGFloat) {
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(width)
    context.replacePathWithStrokedPath()
    context.clip()
    verticalGradient(gradient, in: context, top: top, bottom: bottom)
    context.restoreGState()
}

/// Fine monochrome grain, drawn faintly over gradients so they don't band in 8-bit.
func grain(_ size: CGSize = canvas) -> CGImage {
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
    let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    return ciContext.createCGImage(mono, from: CGRect(origin: .zero, size: size))!
}

// MARK: - The battery

/// The battery's geometry, centred on the tile. The body sits a little left of centre so the body and nub together
/// look centred. Inside the glass body is a recessed track, and in it the lit fill.
enum Battery {
    static let body = CGRect(x: 182, y: 380, width: 604, height: 264)
    static let radius: CGFloat = 94
    static let nub = CGRect(x: body.maxX + 16, y: body.midY - 58, width: 42, height: 116)
    static let track = body.insetBy(dx: 19, dy: 19)
    static let trackRadius = radius - 19
    static let charge: CGFloat = 0.45  // where the white charge ends, as a fraction of the track
    static let gap: CGFloat = 5  // the seam between segments, where the track shows through

    /// The apps draining it: a bright top colour, a deeper bottom one, and each one's share of the track.
    static let slices: [(top: UInt32, bottom: UInt32, share: CGFloat)] = [
        (0xFF6990, 0xE42A5C, 0.125),  // pink
        (0xFFA35C, 0xF06A22, 0.095),  // orange
        (0xFFDB6E, 0xF4AA20, 0.10),  // amber, wider since the fill's round end takes some of it
    ]

    static var bodyPath: CGPath { continuousRect(body, radius: radius) }
    static var trackPath: CGPath { continuousRect(track, radius: trackRadius) }

    /// A half-round terminal nub, flat against the body.
    static var nubPath: CGPath {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 6, bottomLeading: 6, bottomTrailing: nub.width, topTrailing: nub.width), style: .continuous)
        return shape.path(in: nub).cgPath
    }

    /// The horizontal extent of each lit segment: the white charge, then the slices.
    static var segments: [(minX: CGFloat, maxX: CGFloat, top: UInt32, bottom: UInt32)] {
        var result: [(CGFloat, CGFloat, UInt32, UInt32)] = [(track.minX, track.minX + track.width * charge, 0xFFFFFF, 0xD3DBF6)]
        var x = track.minX + track.width * charge
        for slice in slices {
            let width = track.width * slice.share
            result.append((x + gap, x + width, slice.top, slice.bottom))
            x += width
        }
        return result
    }

    /// The lit fill: a capsule from the start of the track to the end of the last slice, rounded at both ends.
    static var fillPath: CGPath {
        continuousRect(CGRect(x: track.minX, y: track.minY, width: segments.last!.maxX - track.minX, height: track.height), radius: trackRadius)
    }
}

/// Paints the lit fill, each segment clipped to the fill's capsule.
func paintFill(in context: CGContext, flat: Bool) {
    context.saveGState()
    context.addPath(Battery.fillPath)
    context.clip()
    for segment in Battery.segments {
        let rect = CGRect(x: segment.minX, y: Battery.track.minY, width: segment.maxX - segment.minX, height: Battery.track.height)
        context.saveGState()
        context.clip(to: rect)
        if flat {
            context.setFillColor(color(segment.top))
            context.fill(rect)
        } else {
            verticalGradient(gradient([(segment.top, 1, 0.1), (segment.bottom, 1, 1)]), in: context, top: rect.maxY, bottom: rect.minY)
        }
        context.restoreGState()
    }
    context.restoreGState()
}

/// An inner shadow inside `path`, cast by its edge from `offset` away.
func innerShadow(_ path: CGPath, in context: CGContext, offset: CGFloat, blur: CGFloat, _ shade: CGColor) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.addRect(path.boundingBox.insetBy(dx: -300, dy: -300))
    context.addPath(path)
    context.setShadow(offset: CGSize(width: 0, height: offset), blur: blur, color: shade)
    context.setFillColor(color(0x000000))
    context.fillPath(using: .evenOdd)
    context.restoreGState()
}

func drawBattery(in context: CGContext) {
    let body = Battery.body
    let track = Battery.track

    // 1. Contact shadow: a dark, soft pool below the battery, and a wider ambient one, so it floats above the tile.
    //    The glass is frosted, so the shadows are cut away from under it rather than showing through as a smudge.
    for (offset, inset, alpha, blur) in [(-24.0, 26.0, 0.8, 22.0), (-52.0, -12.0, 0.5, 56.0)] {
        let shadow = layer { layer in
            layer.addPath(continuousRect(body.offsetBy(dx: 0, dy: offset).insetBy(dx: inset, dy: 8), radius: Battery.radius))
            layer.setFillColor(color(0x05061C, alpha))
            layer.fillPath()
        }
        let cutOut = layer { layer in
            layer.draw(blurred(shadow, blur), in: CGRect(origin: .zero, size: canvas))
            layer.setBlendMode(.destinationOut)
            layer.addPath(Battery.bodyPath)
            layer.addPath(Battery.nubPath)
            layer.fillPath()
        }
        composite(cutOut, in: context, blend: .multiply)
    }

    // 2. Light bloom: the lit fill glows through the glass onto the tile around it.
    composite(blurred(layer { paintFill(in: $0, flat: true) }, 50), in: context, blend: .screen, alpha: 0.6)

    // 3. The glass shell: a frosted, translucent body and nub that let the tile show through.
    let frost = gradient([(0xDCE3FF, 0.44, 0), (0xA6B2FF, 0.26, 0.55), (0xA6B2FF, 0.34, 1)])
    for path in [Battery.bodyPath, Battery.nubPath] {
        context.saveGState()
        context.addPath(path)
        context.clip()
        verticalGradient(frost, in: context, top: body.maxY, bottom: body.minY)
        context.restoreGState()
    }

    // 4. The track: a recessed channel in the glass, darker and shaded along its top edge.
    context.saveGState()
    context.addPath(Battery.trackPath)
    context.clip()
    verticalGradient(gradient([(0x10144A, 0.55, 0), (0x232A7A, 0.4, 1)]), in: context, top: track.maxY, bottom: track.minY)
    context.restoreGState()
    innerShadow(Battery.trackPath, in: context, offset: -10, blur: 18, color(0x05061C, 0.6))

    // 5. The fill: the white charge and the app slices, lit from above, with a shade along the bottom for volume
    //    and a thin bright lip along the top.
    paintFill(in: context, flat: false)
    innerShadow(Battery.fillPath, in: context, offset: 14, blur: 26, color(0x1A1F5C, 0.4))
    let lip = gradient([(0xFFFFFF, 0.9, 0), (0xFFFFFF, 0, 0.35)])
    gradientStroke(Battery.fillPath, width: 4, lip, in: context, top: track.maxY, bottom: track.minY)

    // 6. Volume: an inner shadow along the bottom of the shell, so the whole battery reads as one rounded object.
    innerShadow(Battery.bodyPath, in: context, offset: 16, blur: 34, color(0x10133F, 0.45))

    // 7. The refraction band: a soft sheet of light across the top of the shell, over the fill, its edges blurred
    //    like light bending through thick glass.
    let band = layer { layer in
        layer.addPath(Battery.bodyPath)
        layer.clip()
        layer.addPath(continuousRect(CGRect(x: body.minX + 24, y: body.maxY - 104, width: body.width - 48, height: 94), radius: 70))
        layer.clip()
        verticalGradient(gradient([(0xFFFFFF, 0.6, 0), (0xFFFFFF, 0.12, 0.5), (0xFFFFFF, 0, 1)]), in: layer, top: body.maxY - 10, bottom: body.maxY - 104)
    }
    composite(blurred(band, 4), in: context)

    // 8. Specular rims: a bright edge where the top of the glass catches the light, and a softer bounce along the
    //    bottom, on both the body and the nub.
    let rim = gradient([(0xFFFFFF, 0.95, 0), (0xFFFFFF, 0.25, 0.3), (0xFFFFFF, 0.04, 0.6), (0xFFFFFF, 0.32, 1)])
    gradientStroke(Battery.bodyPath, width: 5, rim, in: context, top: body.maxY, bottom: body.minY)
    gradientStroke(Battery.nubPath, width: 4, rim, in: context, top: Battery.nub.maxY, bottom: Battery.nub.minY)
}

// MARK: - The tile

func drawIcon(in context: CGContext) {
    let shape = continuousRect(tile, radius: tileRadius)

    // Drop shadow, like Apple's icon template: a wide soft one and a tight one at the base.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.32))
    context.addPath(shape)
    context.setFillColor(color(0x1A1F55))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: color(0x000000, 0.25))
    context.addPath(shape)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    // Background: midnight blue at the top falling to a deep indigo, lit from above.
    verticalGradient(
        gradient([(0x2A3888, 1, 0), (0x1B2262, 1, 0.45), (0x121340, 1, 0.8), (0x0C0A2B, 1, 1)]), in: context, top: tile.maxY, bottom: tile.minY)

    // A hint of violet low on the right, so the indigo isn't flat.
    radialGlow(gradient([(0x6A3FC8, 0.35, 0), (0x6A3FC8, 0, 1)]), in: context, at: CGPoint(x: 820, y: 160), radius: 520)

    // A gentle bloom of light behind the battery, and a cool glow from above.
    radialGlow(gradient([(0x7F8EFF, 0.46, 0), (0x7F8EFF, 0, 1)]), in: context, at: CGPoint(x: 490, y: 530), radius: 420)
    radialGlow(gradient([(0x9FC2FF, 0.14, 0), (0x9FC2FF, 0, 1)]), in: context, at: CGPoint(x: 512, y: tile.maxY + 80), radius: 520)

    // Grain, too faint to see, to keep the dark gradients from banding.
    composite(grain(), in: context, blend: .overlay, alpha: 0.05)

    drawBattery(in: context)
    context.restoreGState()

    // The tile's glass edge: bright along the top, faint down the sides, a little bounce light at the bottom.
    let edge = continuousRect(tile.insetBy(dx: 1.5, dy: 1.5), radius: tileRadius - 1.5)
    let rim = gradient([(0xFFFFFF, 0.5, 0), (0xFFFFFF, 0.1, 0.25), (0xFFFFFF, 0.04, 0.7), (0xFFFFFF, 0.16, 1)])
    gradientStroke(edge, width: 3, rim, in: context, top: tile.maxY, bottom: tile.minY)
}

// MARK: - Output

/// Downsamples the master with a Lanczos filter, which keeps small sizes crisp.
func png(_ master: CGImage, pixels: Int) -> Data {
    var image = master
    if pixels != master.width {
        let scale = CGFloat(pixels) / CGFloat(master.width)
        let input = CIImage(cgImage: master)
        let filter = CIFilter(name: "CILanczosScaleTransform")!
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1, forKey: kCIInputAspectRatioKey)
        image = ciContext.createCGImage(filter.outputImage!, from: CGRect(x: 0, y: 0, width: pixels, height: pixels))!
    }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let master = layer { drawIcon(in: $0) }
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "WatchMyBattery/Assets.xcassets/AppIcon.appiconset")

// (point size, scale) pairs required for a macOS app icon.
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try png(master, pixels: points * scale).write(to: iconSet.appending(path: name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appending(path: "Contents.json"))

let docs = root.appending(path: "docs")
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
try png(master, pixels: 1024).write(to: docs.appending(path: "logo.png"))
print("Icon written to \(iconSet.path) and docs/logo.png")
