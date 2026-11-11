import Foundation

/// Whether a new reading differs enough from the one on screen to be worth
/// showing.
///
/// The panel measures apps every two seconds, and the smoothed watts move a
/// little every time. Showing each wiggle redraws the whole panel for a
/// change nobody can see: a fraction of a point in a slice, the same minutes
/// in the labels. Holding a value until it has moved by ``relative`` (or
/// ``absolute``, for tiny ones) keeps what's shown within that much of the
/// truth, at a fraction of the redraws.
public struct DisplayThreshold: Sendable, Equatable {
    /// A change of this share of the value shows: 2%, about a minute in a 48 minute estimate.
    public var relative: Double
    /// And one of this much, whatever the share, so values near zero don't flicker in and out.
    public var absolute: Double

    public init(relative: Double = 0.02, absolute: Double = 0.01) {
        self.relative = relative
        self.absolute = absolute
    }

    public static let watts = DisplayThreshold()

    /// `new` is far enough from `shown` to be shown instead. Appearing or disappearing always counts.
    public func isVisible(from shown: Double?, to new: Double?) -> Bool {
        guard let shown, let new else { return (shown == nil) != (new == nil) }
        let change = abs(new - shown)
        return change > absolute && change > abs(shown) * relative
    }
}
