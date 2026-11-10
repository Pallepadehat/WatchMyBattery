import AppKit
import SwiftUI

/// Picks a colour that represents an app, from its icon: Figma's purple,
/// Xcode's blue, Music's pink.
enum IconTint {
    static func color(of icon: NSImage) -> Color {
        guard let pixels = pixels(of: icon) else { return fallback }

        // Weigh each pixel's hue by how colourful and opaque it is; greys and transparent edges don't count.
        let bucketCount = 24
        var weights = [Double](repeating: 0, count: bucketCount)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: bucketCount)
        for pixel in pixels {
            let color = NSColor(srgbRed: pixel.r, green: pixel.g, blue: pixel.b, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            let weight = Double(saturation * saturation * brightness * pixel.a)
            guard weight > 0.02 else { continue }
            let bucket = min(Int(hue * CGFloat(bucketCount)), bucketCount - 1)
            weights[bucket] += weight
            sums[bucket].r += Double(pixel.r) * weight
            sums[bucket].g += Double(pixel.g) * weight
            sums[bucket].b += Double(pixel.b) * weight
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0.5 else {
            return fallback
        }
        let average = NSColor(
            srgbRed: sums[best].r / weights[best], green: sums[best].g / weights[best],
            blue: sums[best].b / weights[best], alpha: 1)

        // Lift it into a vivid, readable range, so every slice looks like it belongs together.
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return Color(
            hue: hue, saturation: min(max(saturation, 0.55), 0.8), brightness: min(max(brightness, 0.75), 0.9))
    }

    /// Used for icons with no real colour in them.
    static let fallback = Color(hue: 0.62, saturation: 0.35, brightness: 0.7)

    private struct Pixel {
        let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    }

    /// The icon drawn small: plenty for picking a colour, and cheap.
    private static func pixels(of icon: NSImage) -> [Pixel]? {
        let side = 24
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        context.draw(image, in: rect)
        guard let data = context.data else { return nil }

        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        return (0..<(side * side)).compactMap { index in
            let alpha = CGFloat(bytes[index * 4 + 3]) / 255
            guard alpha > 0.5 else { return nil }
            // Undo premultiplication.
            return Pixel(
                r: CGFloat(bytes[index * 4]) / 255 / alpha, g: CGFloat(bytes[index * 4 + 1]) / 255 / alpha,
                b: CGFloat(bytes[index * 4 + 2]) / 255 / alpha, a: alpha)
        }
    }
}
