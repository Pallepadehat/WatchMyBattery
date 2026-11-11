import Foundation

/// Whether macOS shows its own battery in the menu bar, next to ours.
///
/// Control Center keeps a set of flags for each of its items, `Battery`
/// among them, in its preferences: 2 when the item is in the menu bar, 8
/// when it's been taken out ("Don't Show in Menu Bar"), 16 when it's in
/// Control Center itself. The panel's "Two batteries in your menu bar?" tip
/// only makes sense while the built-in battery is still there.
public enum ControlCenterBattery {
    /// The preferences domain Control Center keeps its items in (per host).
    public static let domain = "com.apple.controlcenter"
    /// The battery item's key in it.
    public static let key = "Battery"

    static let shownInMenuBar = 2
    static let hiddenFromMenuBar = 8

    /// `true` when the built-in battery is in the menu bar, `false` when it's been hidden, `nil` when the flags
    /// don't say (a Mac that never changed the setting, or a future macOS that keeps it elsewhere).
    public static func isShownInMenuBar(flags: Int?) -> Bool? {
        guard let flags else { return nil }
        if flags & hiddenFromMenuBar != 0 { return false }
        if flags & shownInMenuBar != 0 { return true }
        return nil
    }
}
