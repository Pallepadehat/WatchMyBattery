import AppKit
import SwiftUI

/// One slice's worth of power right now: an app, a program that isn't one (a command run in a terminal, Docker's
/// engine), or a part of macOS you'd recognise (Spotlight indexing, iCloud syncing).
struct AppUsage: Identifiable, Equatable {
    enum Kind: Equatable {
        /// An app: macOS can show it and ask it to quit.
        case app
        /// A command-line program or background process of yours, quit the way Ctrl-C or `kill` would.
        case program
        /// Part of macOS. It can't be quit, and it calms down by itself.
        case macOS
    }

    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage
    /// A colour taken from the app's icon, for its slice of the battery.
    let tint: Color
    var watts: Double
    var kind: Kind = .app
    /// A command run in a terminal (or an editor's terminal), shown with the icon of the app it runs in: its slice adds a
    /// small terminal badge, so it doesn't read as that app.
    var isCommand = false
    /// What it's doing, for a part of macOS ("Indexing files so Spotlight can find them."), or where a program runs
    /// ("Running in Ghostty.").
    var detail: String? = nil
    /// Every process this slice stands for, when it's several of macOS's (Spotlight has a few indexers); the one
    /// otherwise.
    var members: [pid_t] = []

    var isApp: Bool { kind == .app }
    var canQuit: Bool { kind != .macOS }
    var owners: Set<pid_t> { members.isEmpty ? [id] : Set(members) }

    static func == (lhs: AppUsage, rhs: AppUsage) -> Bool {
        lhs.id == rhs.id && lhs.watts == rhs.watts && lhs.name == rhs.name && lhs.members == rhs.members
    }
}
