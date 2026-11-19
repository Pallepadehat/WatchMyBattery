import AppKit
import SwiftUI

/// The parts of macOS that are worth a slice of their own, by the processes that do their work: Spotlight's indexers,
/// iCloud's sync, Photos' analysis. Each gets the icon of the app it belongs with, so it looks like itself.
///
/// macOS has hundreds of processes; only those that do something you'd recognise, and that can use real power, are
/// here. The rest stay in Display & System, where they're listed by name.
enum MacOSServices {
    struct Service {
        let name: String
        let iconPath: String
        let detail: String
        /// Process names; a trailing `*` matches the start.
        let processes: [String]
    }

    static let all: [Service] = [
        Service(
            name: String(localized: "Spotlight"), iconPath: "/System/Library/CoreServices/Spotlight.app",
            detail: String(localized: "Indexing files so Spotlight can find them. It settles once it's caught up."),
            processes: ["mds", "mds_stores", "mdworker", "mdworker_shared", "mdsync", "mdbulkimport", "corespotlightd", "spotlightknowledged"]),
        Service(
            name: String(localized: "iCloud"), iconPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/iCloud Drive.app",
            detail: String(localized: "Syncing files and data with iCloud."),
            processes: ["bird", "cloudd", "fileproviderd", "clouddocsd", "CloudKeychainProxy"]),
        Service(
            name: String(localized: "Photos Analysis"), iconPath: "/System/Applications/Photos.app",
            detail: String(localized: "Finding faces, scenes and memories in your photos. It mostly works while you're away."),
            processes: ["photoanalysisd", "mediaanalysisd", "mediaanalysisd-access", "photolibraryd", "cloudphotod"]),
        Service(
            name: String(localized: "Time Machine"), iconPath: "/System/Applications/Time Machine.app",
            detail: String(localized: "Backing up."), processes: ["backupd", "backupd-helper"]),
        Service(
            name: String(localized: "Software Update"), iconPath: "/System/Library/CoreServices/Software Update.app",
            detail: String(localized: "Checking for and downloading updates."),
            processes: ["softwareupdated", "SoftwareUpdateNotificationManager", "mobileassetd", "UpdateBrainService", "com.apple.MobileSoftwareUpdate*"]),
        Service(
            name: String(localized: "Window Server"), iconPath: "/System/Applications/Mission Control.app",
            detail: String(localized: "Draws everything on screen. More windows, animations and displays keep it busier."),
            processes: ["WindowServer"]),
        Service(
            name: String(localized: "Siri & Apple Intelligence"), iconPath: "/System/Applications/Siri.app",
            detail: String(localized: "Siri and Apple Intelligence, working in the background."),
            processes: [
                "Siri*", "siri*", "assistantd", "generativeexperiencesd", "intelligenceplatformd", "modelmanagerd", "TGOnDeviceInferenceProviderService",
                "knowledgeconstructiond",
            ]),
        Service(
            name: String(localized: "Sound"), iconPath: "/System/Applications/Utilities/Audio MIDI Setup.app",
            detail: String(localized: "Playing and processing sound."), processes: ["coreaudiod", "audiomxd", "audioaccessoryd"]),
        Service(
            name: String(localized: "Wi‑Fi & Network"), iconPath: "/System/Library/CoreServices/WiFiAgent.app",
            detail: String(localized: "Wi‑Fi, network connections and downloads in the background."),
            processes: ["airportd", "wifid", "wifip2pd", "com.apple.DriverKit-AppleBCMWLAN", "mDNSResponder", "nsurlsessiond", "configd", "symptomsd"]),
        Service(
            name: String(localized: "Messages & FaceTime"), iconPath: "/System/Applications/Messages.app",
            detail: String(localized: "Messages, FaceTime and notifications arriving in the background."),
            processes: ["imagent", "identityservicesd", "apsd", "callservicesd", "IMDPersistenceAgent"]),
        Service(
            name: String(localized: "Logs & Diagnostics"), iconPath: "/System/Applications/Utilities/Console.app",
            detail: String(localized: "Logging, and reports about crashes and hangs."),
            processes: ["logd", "diagnosticd", "ReportCrash", "spindump", "sysdiagnose*", "analyticsd", "osanalyticshelper", "tailspind"]),
        Service(
            name: String(localized: "Security Checks"), iconPath: "/System/Library/CoreServices/Applications/Keychain Access.app",
            detail: String(localized: "Checking apps and files are safe to open, such as scanning new apps."),
            processes: ["XProtect*", "syspolicyd", "trustd", "securityd", "amfid", "MRT"]),
        Service(
            name: String(localized: "macOS Kernel"), iconPath: "/System/Library/CoreServices/Applications/About This Mac.app",
            detail: String(localized: "The core of macOS: memory, files, devices, and keeping the Mac cool."),
            processes: ["kernel_task"]),
    ]

    /// The service a process belongs to, by its name.
    static func service(forProcessNamed name: String) -> Service? {
        if let found = exact[name] { return found }
        return prefixed.first { name.hasPrefix($0.prefix) }?.service
    }

    private static let exact: [String: Service] = {
        var map: [String: Service] = [:]
        for service in all {
            for process in service.processes where !process.hasSuffix("*") { map[process] = service }
        }
        return map
    }()

    private static let prefixed: [(prefix: String, service: Service)] = all.flatMap { service in
        service.processes.filter { $0.hasSuffix("*") }.map { (String($0.dropLast()), service) }
    }
}

/// Real icons for programs that aren't apps, from the apps installed on this Mac: `ollama` gets Ollama's, `docker`
/// Docker's, `code` Visual Studio Code's. Only an exact name (or a well-known alias) counts, so nothing borrows an icon
/// that isn't its own. The Applications folders are listed once, on first use: a few hundred names, a millisecond.
enum InstalledApps {
    @MainActor static func icon(forCommand name: String) -> NSImage? {
        for candidate in candidates(for: name) {
            if let path = index[normalized(candidate)] { return NSWorkspace.shared.icon(forFile: path) }
        }
        return nil
    }

    /// The name itself, a known alias, and the name without a daemon's or server's ending (`ollama-server` → Ollama).
    static func candidates(for name: String) -> [String] {
        let lower = name.lowercased()
        var names = [lower]
        if let alias = aliases.first(where: { lower == $0.key || lower.hasPrefix($0.key + ".") })?.value { names.append(alias) }
        for ending in ["-server", "-daemon", "-helper", "-cli", " helper", "d"] where lower.hasSuffix(ending) && lower.count > ending.count + 2 {
            names.append(String(lower.dropLast(ending.count)))
        }
        return names
    }

    static let aliases: [String: String] = [
        "code": "Visual Studio Code", "com.docker": "Docker", "docker": "Docker", "orb": "OrbStack", "orbstack": "OrbStack",
        "postgres": "Postgres", "postmaster": "Postgres", "lms": "LM Studio", "subl": "Sublime Text", "zed": "Zed", "cursor": "Cursor",
        "windsurf": "Windsurf", "tailscaled": "Tailscale", "colima": "Colima", "claude": "Claude", "ollama": "Ollama", "utm": "UTM",
        "qemu-system-aarch64": "UTM", "redis-server": "Redis", "mongod": "MongoDB Compass", "mysqld": "MySQLWorkbench",
    ]

    static func normalized(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    @MainActor private static let index: [String: String] = {
        var index: [String: String] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Your own apps only: macOS's would hand `mail` Mail's icon, though it's a different program.
        for folder in ["/Applications", "/Applications/Utilities", home + "/Applications", home + "/Applications/Chrome Apps"] {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let key = normalized(String(name.dropLast(4)))
                if index[key] == nil { index[key] = folder + "/" + name }
            }
        }
        return index
    }()
}

/// Colours for programs with no icon to take one from: macOS's own system colours, picked by the name, so a program
/// keeps its colour and two side by side differ.
enum ProgramTint {
    static func color(for name: String) -> Color {
        let palette: [NSColor] = [.systemIndigo, .systemTeal, .systemOrange, .systemBrown, .systemMint, .systemCyan, .systemBlue, .systemPurple]
        let hash = name.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        // Softened towards grey, like the colours taken from app icons: macOS's system colours at full strength shout.
        let base = palette[Int(hash % UInt64(palette.count))].usingColorSpace(.sRGB) ?? .systemBlue
        return Color(nsColor: base.blended(withFraction: 0.32, of: NSColor(white: 0.5, alpha: 1)) ?? base)
    }
}
