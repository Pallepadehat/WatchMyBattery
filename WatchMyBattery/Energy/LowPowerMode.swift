import AppKit
import BatteryKit
import Foundation
import OSLog
import Observation
import ServiceManagement

/// Turns Low Power Mode on and off.
///
/// macOS has no API for apps to change it; it takes `pmset`, run as root.
/// So WatchMyBattery comes with a tiny helper, `WatchMyBatteryHelper`, that
/// does just that. macOS asks you once to allow it, in System Settings ›
/// Login Items, and from then on the switch just works, without a password.
///
/// Builds the helper can't be used from (an ad hoc signed build, say) fall back
/// to asking for an administrator's password each time. The battery monitor
/// notices the change through `ProcessInfo`, as it does when it's changed
/// anywhere else.
@Observable
final class LowPowerMode {
    /// Where the helper stands.
    enum HelperState: Equatable {
        /// Not in this build, or the build isn't signed by a team: changes ask for a password instead.
        case unavailable
        /// Not set up yet. The first change sets it up.
        case notRegistered
        /// Waiting for you to allow it in System Settings › Login Items.
        case requiresApproval
        case enabled
    }

    /// This Mac has Low Power Mode (most MacBooks from 2016 on). `false` until checked.
    private(set) var isSupported = false
    /// Waiting for the helper, the password prompt or approval in System Settings.
    private(set) var isChanging = false
    private(set) var helperState: HelperState = .unavailable
    /// The suggestion to turn it on was dismissed; it comes back after the next charge.
    var isSuggestionDismissed = false

    /// The level at and below which the panel suggests turning it on, like the iPhone does.
    static let suggestionLevel = 20

    @ObservationIgnored private let service = SMAppService.daemon(plistName: HelperIdentity.plistName)
    /// The change to make once the helper is allowed in System Settings.
    @ObservationIgnored private var pendingValue: Bool?
    @ObservationIgnored private var approvalWatch: Task<Void, Never>?

    /// Checks once whether `pmset` knows about Low Power Mode on this Mac, and where the helper stands.
    func checkSupport() {
        refreshHelperState()
        Task.detached {
            let output = (try? Self.run("/usr/bin/pmset", ["-g"]))?.output ?? ""
            let supported = output.contains("lowpowermode")
            await MainActor.run { self.isSupported = supported }
        }
    }

    func refreshHelperState() {
        let state: HelperState
        if HelperIdentity.requirement(forIdentifier: HelperIdentity.label) == nil {
            state = .unavailable
        } else {
            switch service.status {
            case .enabled: state = .enabled
            case .requiresApproval: state = .requiresApproval
            // Before it's first registered, macOS reports the helper as not found ("record not found")
            // rather than not registered, so trust the bundle: if the plist is there, it can be set up.
            case .notRegistered, .notFound: state = Self.isHelperInBundle ? .notRegistered : .unavailable
            @unknown default: state = .unavailable
            }
        }
        if state != helperState { helperState = state }
    }

    /// This build comes with the helper and its launchd property list.
    private static let isHelperInBundle = FileManager.default.fileExists(
        atPath: Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchDaemons/\(HelperIdentity.plistName)").path)

    /// Turns Low Power Mode on or off: through the helper when it's allowed, after setting it up the
    /// first time, or else with a password prompt.
    func set(_ on: Bool) {
        guard isSupported, !isChanging else { return }
        refreshHelperState()
        switch helperState {
        case .enabled:
            isChanging = true
            Task {
                let failure = await HelperClient.setLowPowerMode(on)
                self.isChanging = false
                if let failure {
                    Logger.app.error("The helper couldn't change Low Power Mode: \(failure, privacy: .public)")
                    self.setWithPassword(on)
                }
            }
        case .notRegistered, .requiresApproval:
            setUpHelper(thenSet: on)
        case .unavailable:
            setWithPassword(on)
        }
    }

    /// Registers the helper, which macOS wants you to allow in System Settings › Login Items.
    /// Opens that page, and makes the change as soon as you allow it.
    func setUpHelper(thenSet value: Bool? = nil) {
        if helperState == .notRegistered {
            do {
                try service.register()
            } catch {
                // "Operation not permitted" here means it's registered and waiting for approval.
                Logger.app.notice("Registering the helper: \(error.localizedDescription, privacy: .public)")
            }
            refreshHelperState()
        }
        switch helperState {
        case .enabled:
            if let value { set(value) }
        case .requiresApproval:
            pendingValue = value
            isChanging = value != nil
            SMAppService.openSystemSettingsLoginItems()
            watchForApproval()
        case .notRegistered, .unavailable:
            // Registering didn't work: ask for the password this once.
            Logger.app.error("The helper couldn't be set up, so asking for a password instead")
            if let value { setWithPassword(value) }
        }
    }

    /// Checks every second, for a few minutes, whether the helper has been allowed.
    private func watchForApproval() {
        approvalWatch?.cancel()
        approvalWatch = Task {
            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                refreshHelperState()
                if helperState == .enabled {
                    let value = pendingValue
                    pendingValue = nil
                    isChanging = false
                    if let value { set(value) }
                    return
                }
            }
            pendingValue = nil
            isChanging = false
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

    // MARK: - Without the helper

    /// Runs `pmset` with `osascript`'s administrator privileges, which asks for a password every time.
    private func setWithPassword(_ on: Bool) {
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

/// Talks to `WatchMyBatteryHelper` over XPC.
private nonisolated enum HelperClient {
    /// Returns `nil` when it worked, or what went wrong.
    static func setLowPowerMode(_ on: Bool) async -> String? {
        guard let requirement = HelperIdentity.requirement(forIdentifier: HelperIdentity.label) else {
            return "This build isn't signed by a team"
        }
        let connection = NSXPCConnection(machServiceName: HelperIdentity.label, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: LowPowerModeHelperProtocol.self)
        // Only talk to our own helper, signed by the same team as the app.
        connection.setCodeSigningRequirement(requirement)
        connection.resume()
        defer { connection.invalidate() }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = Once(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(error.localizedDescription)
            }
            guard let helper = proxy as? LowPowerModeHelperProtocol else {
                once.resume("The helper isn't answering")
                return
            }
            helper.setLowPowerMode(on) { failure in once.resume(failure) }
        }
    }

    /// Resumes a continuation once, whichever of the reply and the error handler comes first.
    private final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<String?, Never>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<String?, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: String?) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
    }
}
