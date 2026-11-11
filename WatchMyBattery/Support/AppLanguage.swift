import AppKit

/// The language WatchMyBattery shows itself in.
///
/// It's the same per-app setting as System Settings › General › Language &
/// Region › Applications: the `AppleLanguages` preference in the app's own
/// domain. macOS reads it when the app starts, so a change applies after a
/// relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Whatever the Mac is set to.
    case system
    case english = "en"
    case danish = "da"

    var id: Self { self }

    /// Each language in its own words, so you can find yours whatever language the app is in now.
    var title: String {
        switch self {
        case .system: String(localized: "System Default")
        case .english: "English"
        case .danish: "Dansk"
        }
    }

    private static let key = "AppleLanguages"

    /// The language chosen for this app, read from its own preferences only (not the system's).
    static var chosen: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let first = (domain?[key] as? [String])?.first else { return .system }
        return allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
    }

    /// The language the app is showing right now, which a change only affects after a relaunch.
    static let current = chosen

    static func choose(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
    }

    /// Quits and opens again, so a new language takes effect.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this copy to quit, then open a fresh one.
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
