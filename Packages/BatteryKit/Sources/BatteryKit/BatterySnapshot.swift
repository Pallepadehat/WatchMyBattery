import Foundation

/// Everything the menu bar icon and the panel need to know about the battery
/// at one moment in time.
public struct BatterySnapshot: Sendable, Equatable {
    /// Where the Mac is drawing power from.
    public enum PowerSource: Sendable, Hashable {
        case battery
        case powerAdapter
    }

    /// What the battery itself is doing.
    public enum ChargeState: Sendable, Hashable {
        case discharging
        case charging
        /// Plugged in and full.
        case charged
        /// Plugged in but holding its charge (Optimized Charging, a charge limit, or a weak adapter).
        case notCharging
    }

    /// Charge level, 0–100.
    public var percentage: Int
    public var powerSource: PowerSource
    public var chargeState: ChargeState
    /// Time until empty while discharging, or until full while charging.
    /// `nil` while macOS is still calculating, or when it doesn't apply.
    public var timeRemaining: TimeInterval?
    public var isLowPowerModeOn: Bool
    /// `false` on Macs without a battery (a Mac mini, say).
    public var hasBattery: Bool
    /// The level macOS charges to, 1–100: 80 while Optimized Battery Charging holds the battery there, otherwise 100.
    public var chargeTarget: Int

    public init(
        percentage: Int,
        powerSource: PowerSource,
        chargeState: ChargeState,
        timeRemaining: TimeInterval?,
        isLowPowerModeOn: Bool = false,
        hasBattery: Bool = true,
        chargeTarget: Int = 100
    ) {
        self.percentage = min(max(percentage, 0), 100)
        self.powerSource = powerSource
        self.chargeState = chargeState
        self.timeRemaining = timeRemaining
        self.isLowPowerModeOn = isLowPowerModeOn
        self.hasBattery = hasBattery
        self.chargeTarget = min(max(chargeTarget, 1), 100)
    }

    /// Charging (or holding its charge) short of full, on purpose.
    public var hasChargeLimit: Bool { isPluggedIn && chargeTarget < 100 }

    /// How full it is, as a share of its target, 0–1.
    public var progressToTarget: Double { min(Double(percentage) / Double(chargeTarget), 1) }

    /// Reached its target, so it holds there rather than charging on.
    public var isAtTarget: Bool { percentage >= chargeTarget }

    /// The charge level as a fraction, 0–1.
    public var level: Double { Double(percentage) / 100 }

    public var isCharging: Bool { chargeState == .charging }
    public var isPluggedIn: Bool { powerSource == .powerAdapter }

    /// A Mac with no battery: plugged in, nothing to show.
    public static let noBattery = BatterySnapshot(
        percentage: 100, powerSource: .powerAdapter, chargeState: .charged, timeRemaining: nil, hasBattery: false)
}
