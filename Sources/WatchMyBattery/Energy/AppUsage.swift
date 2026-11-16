import AppKit
import SwiftUI

/// One app and how much power it's drawing right now.
struct AppUsage: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage
    /// A colour taken from the app's icon, for its slice of the battery.
    let tint: Color
    var watts: Double

    static func == (lhs: AppUsage, rhs: AppUsage) -> Bool {
        lhs.id == rhs.id && lhs.watts == rhs.watts && lhs.name == rhs.name
    }
}
