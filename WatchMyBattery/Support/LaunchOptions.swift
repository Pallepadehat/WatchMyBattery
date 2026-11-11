import Foundation

/// Launch arguments that work in every build, Release included, for the
/// end-to-end checks in `scripts/e2e.swift`, which have to measure the app
/// as people run it.
nonisolated enum LaunchOptions {
    /// `--isolated <folder>`: runs without touching anything the real app
    /// keeps, so it can run next to it. Settings start from the defaults and
    /// live in their own domain, the history is kept in `folder`, Sparkle
    /// stays off, the keyboard shortcut isn't registered, and the menu bar
    /// icon keeps its own position.
    static let isolatedFolder: URL? = value(after: "--isolated").map { URL(fileURLWithPath: $0, isDirectory: true) }

    static var isIsolated: Bool { isolatedFolder != nil }

    /// Settings for an isolated run, cleared at launch, so every run starts the same.
    static let isolatedDefaultsDomain = "com.pallepadehat.WatchMyBattery.isolated"

    /// `--show-panel`: opens the panel right away.
    static let showsPanel = CommandLine.arguments.contains("--show-panel")

    /// `--pretend-charging`: the battery charging at 62%, to see (or measure) the charging animation on any battery.
    /// Debug builds always understand it; Release builds only in an isolated run, so it can't end up in real use.
    static let pretendsCharging: Bool = {
        #if DEBUG
            return CommandLine.arguments.contains("--pretend-charging")
        #else
            return isIsolated && CommandLine.arguments.contains("--pretend-charging")
        #endif
    }()

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
