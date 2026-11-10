import AppKit
import ImageIO
import Observation

/// The top of macOS's own default wallpaper, behind the menu bar samples in
/// Settings, so they look like a real menu bar.
@Observable
final class Wallpaper {
    /// The strip of wallpaper under the menu bar's right end. `nil` until loaded.
    private(set) var image: NSImage?
    /// Whether the strip under the menu bar is dark, so menu bar items are drawn in white.
    private(set) var isDark = true

    func load() async {
        guard let (image, isDark) = await Task.detached(priority: .utility, operation: { Self.read(Self.defaultPicture) }).value
        else { return }
        self.image = NSImage(cgImage: image, size: .zero)
        self.isDark = isDark
    }

    /// The wallpaper this version of macOS ships with.
    private nonisolated static let defaultPicture = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")

    // MARK: - Reading it

    /// Loads a small copy of the picture and measures how bright its top edge is.
    private nonisolated static func read(_ url: URL) -> (CGImage, Bool)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1000,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        // The strip at the top right, where the menu bar's battery sits, shaped like a sample (3.7 : 1).
        let width = Double(image.width) * 0.35
        let strip = CGRect(x: Double(image.width) - width, y: 0, width: width, height: width / 3.7)
        let top = image.cropping(to: strip) ?? image
        return (top, averageLuminance(ofTopOf: image) < 0.6)
    }

    /// Average brightness, 0–1, of the strip the menu bar sits on.
    private nonisolated static func averageLuminance(ofTopOf image: CGImage) -> Double {
        let width = 32
        let height = 4
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: max(image.height / 20, 1)))
        else { return 0 }
        context.draw(top, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var total = 0.0
        for pixel in 0..<(width * height) {
            let r = Double(bytes[pixel * 4]), g = Double(bytes[pixel * 4 + 1]), b = Double(bytes[pixel * 4 + 2])
            total += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        }
        return total / Double(width * height)
    }
}
