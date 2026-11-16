import AppKit
import BatteryKit
import SwiftUI

/// Picks a colour that represents an app, from its icon: Figma's purple,
/// Xcode's blue, Music's pink. The arithmetic is ``IconPalette``'s; this
/// draws the icon small for it, and remembers the answer.
enum IconTint {
    /// The colour for an app's slice. Worked out once per app (keyed by its bundle identifier, or its name), as
    /// drawing the icon is most of the cost, and the panel, the history and notifications all ask.
    static func color(of icon: NSImage, for key: String) -> Color {
        if let color = cache[key] { return color }
        let color = color(of: icon)
        cache[key] = color
        return color
    }

    /// The colour of an icon, worked out afresh.
    static func color(of icon: NSImage) -> Color {
        guard let color = dominantColor(of: icon) else { return fallback }
        return Color(hue: color.hue, saturation: color.saturation, brightness: color.brightness)
    }

    /// Used for icons with no real colour in them.
    static let fallback = Color(hue: 0.62, saturation: 0.35, brightness: 0.7)

    private static var cache: [String: Color] = [:]

    /// The icon drawn small (plenty for picking a colour, and cheap), handed to ``IconPalette``.
    private static func dominantColor(of icon: NSImage) -> IconPalette.Color? {
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
        let bytes = UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: side * side * 4), count: side * side * 4)
        return IconPalette.dominantColor(rgba: bytes)
    }
}
