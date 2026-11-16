import AppKit

/// Opens pages of System Settings.
enum SystemSettings {
    enum Page: String {
        case battery = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        case controlCenter = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
        case loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        case displays = "x-apple.systempreferences:com.apple.Displays-Settings.extension"
    }

    static func open(_ page: Page) {
        guard let url = URL(string: page.rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}
