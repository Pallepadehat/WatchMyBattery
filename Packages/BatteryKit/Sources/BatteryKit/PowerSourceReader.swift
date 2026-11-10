import Foundation
import IOKit.ps

/// Reads the battery's state from IOPowerSources, the same source the
/// built-in battery menu uses, so the numbers always match macOS.
public enum PowerSourceReader {
    public static func read() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return .noBattery }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSIsPresentKey] as? Bool ?? true
            else { continue }
            return snapshot(from: description, isLowPowerModeOn: lowPower)
        }
        return .noBattery
    }

    /// Builds a snapshot from one power source description. Separate from
    /// `read()` so it can be tested with made-up descriptions.
    static func snapshot(from description: [String: Any], isLowPowerModeOn: Bool) -> BatterySnapshot {
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0

        let onAdapter = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false

        let chargeState: BatterySnapshot.ChargeState
        let minutes: Int?
        switch (onAdapter, isCharging) {
        case (false, _):
            chargeState = .discharging
            minutes = description[kIOPSTimeToEmptyKey] as? Int
        case (true, true):
            chargeState = .charging
            minutes = description[kIOPSTimeToFullChargeKey] as? Int
        case (true, false):
            chargeState = isCharged || percentage >= 100 ? .charged : .notCharging
            minutes = nil
        }

        // macOS reports -1 while it's still working out an estimate, and 0 when there's nothing to estimate.
        let timeRemaining = minutes.flatMap { $0 > 0 ? TimeInterval($0 * 60) : nil }

        return BatterySnapshot(
            percentage: percentage,
            powerSource: onAdapter ? .powerAdapter : .battery,
            chargeState: chargeState,
            timeRemaining: timeRemaining,
            isLowPowerModeOn: isLowPowerModeOn
        )
    }
}
