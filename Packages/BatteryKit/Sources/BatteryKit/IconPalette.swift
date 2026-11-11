import Foundation

/// Picks the colour that represents an app from its icon: Figma's purple,
/// Xcode's blue, Music's pink. The panel gives each app's slice that colour.
///
/// Each pixel's hue counts for how colourful, bright and opaque it is, so
/// greys, white glyphs and soft edges don't. The most common hue wins, and
/// it's lifted into a vivid, readable range, so every slice looks like it
/// belongs with the others. It's plain arithmetic on the pixels, run once per
/// app: no colour objects per pixel.
public enum IconPalette {
    /// A colour as hue, saturation and brightness, each 0–1.
    public struct Color: Equatable, Sendable {
        public var hue: Double
        public var saturation: Double
        public var brightness: Double

        public init(hue: Double, saturation: Double, brightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.brightness = brightness
        }
    }

    /// The hue circle is split into this many slices; the one with the most weight wins.
    static let hueBuckets = 24
    /// An icon needs about this much colourful, opaque area for its colour to count; less, and it's
    /// grey or white enough that ``dominantColor(rgba:)`` returns `nil`.
    static let minimumWeight = 0.5

    /// The icon's colour, from its pixels as premultiplied RGBA bytes (what a bitmap context holds);
    /// `nil` for an icon with no real colour in it.
    public static func dominantColor(rgba bytes: UnsafeBufferPointer<UInt8>) -> Color? {
        var weights = [Double](repeating: 0, count: hueBuckets)
        var red = [Double](repeating: 0, count: hueBuckets)
        var green = [Double](repeating: 0, count: hueBuckets)
        var blue = [Double](repeating: 0, count: hueBuckets)

        var index = 0
        while index + 3 < bytes.count {
            defer { index += 4 }
            let alpha = Double(bytes[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            // Undo premultiplication.
            let r = min(Double(bytes[index]) / 255 / alpha, 1)
            let g = min(Double(bytes[index + 1]) / 255 / alpha, 1)
            let b = min(Double(bytes[index + 2]) / 255 / alpha, 1)
            let (hue, saturation, brightness) = hsb(r, g, b)
            let weight = saturation * saturation * brightness * alpha
            guard weight > 0.02 else { continue }
            let bucket = min(Int(hue * Double(hueBuckets)), hueBuckets - 1)
            weights[bucket] += weight
            red[bucket] += r * weight
            green[bucket] += g * weight
            blue[bucket] += b * weight
        }

        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > minimumWeight else { return nil }
        let (hue, saturation, brightness) = hsb(red[best] / weights[best], green[best] / weights[best], blue[best] / weights[best])
        return Color(hue: hue, saturation: min(max(saturation, 0.55), 0.8), brightness: min(max(brightness, 0.75), 0.9))
    }

    public static func dominantColor(rgba bytes: [UInt8]) -> Color? {
        bytes.withUnsafeBufferPointer { dominantColor(rgba: $0) }
    }

    /// Hue, saturation and brightness of an RGB colour, all 0–1, the way `NSColor` works them out.
    static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        let saturation = maximum > 0 ? delta / maximum : 0
        guard delta > 0 else { return (0, saturation, maximum) }
        var hue: Double
        if maximum == r {
            hue = (g - b) / delta
        } else if maximum == g {
            hue = 2 + (b - r) / delta
        } else {
            hue = 4 + (r - g) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, maximum)
    }
}
