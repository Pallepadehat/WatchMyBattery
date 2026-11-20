import Foundation

/// Why a plugged-in Mac isn't charging, or is charging slowly, when there's a reason worth telling.
///
/// It only says what the readings show, and nothing rather than guess: a battery held at its charge limit, or by
/// Optimized Battery Charging, already says so in the panel's charge bar, and a pause with no visible cause gets no
/// note at all.
public enum ChargingNote: Sendable, Equatable {
    /// Not charging until the battery cools down: macOS holds charging back above ``BatteryReadings/Warmth/hotFrom``.
    case pausedWhileHot(temperature: Double)
    /// Charging, but held back while the battery is this warm.
    case slowedByHeat(temperature: Double)
    /// The charger can't keep up with the Mac: the Mac draws about all it can give, so the battery isn't charging, or
    /// is even running down.
    case adapterTooWeak(adapterWatts: Int, systemWatts: Double)
    /// Running down on the charger although the Mac draws much less than it's rated for: the charger, the cable or
    /// the port isn't giving its full power (or another app is draining the battery on purpose). `chargerWatts` is
    /// what's actually coming in, when the battery controller says.
    case notGettingFullPower(adapterWatts: Int?, chargerWatts: Double?)
    /// Charging, but slowly: the Mac itself takes most of what the charger gives.
    case chargingSlowly(adapterWatts: Int, systemWatts: Double)
    /// Just short of where it charges to: macOS lets a charged battery drift down a little before topping it up, so it
    /// isn't kept full all the time.
    case restingNearTarget(target: Int)

    /// The note for this moment, if any.
    ///
    /// - Parameters:
    ///   - adapter: the connected charger, when there is one.
    ///   - systemWatts: what the whole Mac draws right now, when it's being measured.
    ///   - chargerWatts: what the Mac is getting from the charger right now, when it's being measured.
    ///   - readings: the battery controller's readings, for its temperature and which way current flows.
    public static func evaluate(
        snapshot: BatterySnapshot, adapter: PowerAdapter?, systemWatts: Double?, chargerWatts: Double? = nil,
        readings: BatteryReadings?
    ) -> ChargingNote? {
        guard snapshot.hasBattery, snapshot.isPluggedIn else { return nil }
        let temperature = readings?.temperature
        let isHot = readings?.warmth == .hot
        let adapterWatts = adapter?.watts

        switch snapshot.chargeState {
        case .notCharging:
            // Held there on purpose, and the charge bar says by whom.
            if snapshot.hasChargeLimit && snapshot.isAtTarget { return nil }
            // Running down on the charger is worth saying whatever else is going on, but why decides what to say: a Mac
            // drawing all the charger can give, or a charger that isn't giving what it should. Only the first is the
            // charger being too small.
            if isRunningFromBattery(readings, systemWatts: systemWatts, chargerWatts: chargerWatts) {
                if let adapterWatts, let systemWatts, isOverloaded(adapterWatts: adapterWatts, systemWatts: systemWatts, share: overloadedShare) {
                    return .adapterTooWeak(adapterWatts: adapterWatts, systemWatts: systemWatts)
                }
                return .notGettingFullPower(adapterWatts: adapterWatts, chargerWatts: chargerWatts)
            }
            // Just short of the target, not charging is simply how macOS tops up, however busy or warm the Mac is.
            if snapshot.percentage >= snapshot.chargeTarget - restingMargin {
                return .restingNearTarget(target: snapshot.chargeTarget)
            }
            if isHot, let temperature { return .pausedWhileHot(temperature: temperature) }
            if let adapterWatts, let systemWatts, isOverloaded(adapterWatts: adapterWatts, systemWatts: systemWatts, share: overloadedShare) {
                return .adapterTooWeak(adapterWatts: adapterWatts, systemWatts: systemWatts)
            }
            return nil
        case .charging:
            if isHot, let temperature { return .slowedByHeat(temperature: temperature) }
            if let adapterWatts, let systemWatts, isOverloaded(adapterWatts: adapterWatts, systemWatts: systemWatts, share: busyShare) {
                return .chargingSlowly(adapterWatts: adapterWatts, systemWatts: systemWatts)
            }
            return nil
        case .charged, .discharging:
            return nil
        }
    }

    /// Not a problem: just how macOS charges.
    public var isResting: Bool {
        if case .restingNearTarget = self { return true }
        return false
    }

    // MARK: - Thresholds

    /// The Mac drawing this share of the charger's watts leaves nothing for the battery. Not the whole of it: a
    /// charger's rating is what it gives at best, before what's lost on the way.
    static let overloadedShare = 0.9
    /// The Mac drawing this share of the charger's watts leaves the battery a trickle.
    static let busyShare = 0.75
    /// Current flowing out of the battery, in amps, beyond what's just measuring noise.
    static let dischargingCurrent = -0.1
    /// How far below its target a battery can rest before not charging needs another reason, in percentage points.
    /// macOS tops up a full battery once it's drifted down about this far.
    static let restingMargin = 5

    /// The Mac taking this many more watts than come in from the charger is the battery making up the difference,
    /// beyond what's just the two readings being taken a moment apart.
    static let shortfallWatts = 1.0

    /// Whether the battery is supplying part of the Mac's power while it's plugged in. What comes in from the
    /// charger against what the Mac draws says so best: both are measured by the same controller at the same time.
    /// Without them, current flowing out of the battery does.
    private static func isRunningFromBattery(_ readings: BatteryReadings?, systemWatts: Double?, chargerWatts: Double?) -> Bool {
        if let systemWatts, let chargerWatts { return systemWatts - chargerWatts >= shortfallWatts }
        guard let current = readings?.current else { return false }
        return current <= dischargingCurrent
    }

    private static func isOverloaded(adapterWatts: Int, systemWatts: Double, share: Double) -> Bool {
        adapterWatts > 0 && systemWatts >= Double(adapterWatts) * share
    }
}
