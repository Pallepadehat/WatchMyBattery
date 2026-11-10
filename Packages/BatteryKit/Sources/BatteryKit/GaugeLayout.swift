import Foundation

/// Lays out the panel's big battery: how wide the charge is, and the slices
/// at the end of it for the apps that will use that charge.
///
/// The whole fill stands for the charge that's left. Each app's slice is
/// its share of the Mac's power draw, so a slice is the part of the
/// remaining charge that app is on track to use. Slices have a minimum
/// width so their icons fit; when the battery is too low to hold them, the
/// plain part shrinks first, and only then do the slices reach past the true
/// level, so the apps can still be dragged out.
public struct GaugeLayout: Equatable, Sendable {
    /// Width of the plain part of the fill, before the slices.
    public let baseWidth: CGFloat
    /// Width of each slice, in the order the shares were given. Shorter than
    /// the shares when they didn't all fit.
    public let sliceWidths: [CGFloat]

    public var fillWidth: CGFloat { baseWidth + sliceWidths.reduce(0, +) }

    /// The left edge of each slice.
    public var sliceOffsets: [CGFloat] {
        var offset = baseWidth
        return sliceWidths.map { width in
            defer { offset += width }
            return offset
        }
    }

    public init(
        width: CGFloat, level: Double, shares: [Double], minimumSliceWidth: CGFloat = 30,
        minimumBaseWidth: CGFloat = 6
    ) {
        let width = max(width, 0)
        let charge = width * CGFloat(min(max(level, 0), 1))
        var slices: [CGFloat] = []
        for share in shares {
            let slice = max(charge * CGFloat(min(max(share, 0), 1)), minimumSliceWidth)
            // Stop adding slices once they'd squeeze the label out of the battery.
            guard minimumBaseWidth + slices.reduce(0, +) + slice <= width else { break }
            slices.append(slice)
        }
        let used = slices.reduce(0, +)
        baseWidth = min(max(charge - used, minimumBaseWidth), width - used)
        sliceWidths = slices
    }
}
