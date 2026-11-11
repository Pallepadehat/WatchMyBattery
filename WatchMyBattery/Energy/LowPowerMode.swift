import BatteryKit
import Foundation
import OSLog
import Observation

/// Turns Low Power Mode on and off.
///
/// macOS has no API for apps to change it, so this runs `pmset`, the same
/// command-line tool System Settings' setting maps to. That needs an
/// administrator, so macOS asks for a password (or Touch ID) each time.
/// The battery monitor notices the change through `ProcessInfo`, as it does
/// when it's changed anywhere else.
@Observable
final class LowPowerMode {
    /// This Mac has Low Power Mode (most MacBooks from 2016 on). `false` until checked.
    private(set) var isSupported = false
    /// Waiting for the password prompt, or for `pmset` to finish.
    private(set) var isChanging = false
    /// The suggestion to turn it on was dismissed; it comes back after the next charge.
    var isSuggestionDismissed = false

    /// The level at and below which the panel suggests turning it on, like the iPhone does.
    static let suggestionLevel = 20

    /// Checks once whether `pmset` knows about Low Power Mode on this Mac.
    func checkSupport() {
        Task.detached {
            let output = (try? Self.run("/usr/bin/pmset", ["-g"]))?.output ?? ""
            let supported = output.contains("lowpowermode")
            await MainActor.run { self.isSupported = supported }
        }
    }

    /// Asks macOS to turn Low Power Mode on or off. Cancelling the password prompt changes nothing.
    func set(_ on: Bool) {
        guard isSupported, !isChanging else { return }
        isChanging = true
        let prompt =
            on
            ? String(localized: "WatchMyBattery wants to turn on Low Power Mode.")
            : String(localized: "WatchMyBattery wants to turn off Low Power Mode.")
        let script =
            "do shell script \"/usr/bin/pmset -a lowpowermode \(on ? 1 : 0)\" with prompt \(Self.appleScriptString(prompt)) with administrator privileges"
        Task.detached {
            var failure: String?
            do {
                let result = try Self.run("/usr/bin/osascript", ["-e", script])
                // -128 is "User canceled", which needs no message.
                if result.status != 0, !result.output.contains("-128") { failure = result.output }
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                if let failure { Logger.app.error("Couldn't change Low Power Mode: \(failure, privacy: .public)") }
                self.isChanging = false
            }
        }
    }

    /// Whether the panel should offer to turn it on: running low on battery, and not dismissed.
    func suggests(for snapshot: BatterySnapshot) -> Bool {
        isSupported && !isSuggestionDismissed && snapshot.hasBattery && snapshot.chargeState == .discharging
            && !snapshot.isLowPowerModeOn && snapshot.percentage <= Self.suggestionLevel
    }

    #if DEBUG
        /// Shows the switch without checking the Mac, for previews.
        func preview(isSupported: Bool) {
            self.isSupported = isSupported
        }
    #endif

    // MARK: - Running commands

    private nonisolated static func run(_ path: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// `text` as an AppleScript string literal.
    private nonisolated static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
