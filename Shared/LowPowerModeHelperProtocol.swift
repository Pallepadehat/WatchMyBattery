import Foundation
import Security

/// The one thing the privileged helper does: turn Low Power Mode on or off.
///
/// Shared by the app and `WatchMyBatteryHelper`. The helper runs as root (as
/// a launchd daemon the user approves once, in System Settings › Login
/// Items), so it accepts nothing but a yes or no, and only from WatchMyBattery
/// itself, signed by the same team as the helper.
@objc nonisolated protocol LowPowerModeHelperProtocol {
    /// Replies with `nil` when it worked, or what went wrong.
    func setLowPowerMode(_ on: Bool, reply: @escaping @Sendable (String?) -> Void)
}

nonisolated enum HelperIdentity {
    /// The daemon's launchd label, which is also its XPC service name.
    static let label = "com.pallepadehat.WatchMyBattery.helper"
    /// The daemon's launchd property list, in `Contents/Library/LaunchDaemons`.
    static let plistName = label + ".plist"
    static let appIdentifier = "com.pallepadehat.WatchMyBattery"

    /// A code signing requirement for `identifier`, signed by Apple-issued
    /// certificate of the same team as this process. `nil` when this process
    /// isn't signed by a team (an ad hoc build), as then there's nothing to
    /// tell the real app from any other program.
    static func requirement(forIdentifier identifier: String) -> String? {
        guard let team = ownTeamIdentifier() else { return nil }
        return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// The team that signed the running process.
    static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let info = info as? [String: Any],
            let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty
        else { return nil }
        return team
    }
}
