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
        // Optimized Battery Charging learns your routine and holds the battery at 80% until you'd need it full.
        let target = onAdapter && Self.flag(description[Self.optimizedChargingKey]) ? Self.optimizedTarget : 100

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
            isLowPowerModeOn: isLowPowerModeOn,
            chargeTarget: target
        )
    }

    /// The key IOPowerSources adds while Optimized Battery Charging holds the battery back. It isn't in the
    /// public headers, so it's spelled out here.
    static let optimizedChargingKey = "Optimized Battery Charging Engaged"
    /// Where Optimized Battery Charging holds the battery.
    static let optimizedTarget = 80

    /// IOKit hands flags over as Booleans or as numbers, depending on the key.
    private static func flag(_ value: Any?) -> Bool {
        (value as? Bool) ?? ((value as? Int).map { $0 != 0 } ?? false)
    }
}
