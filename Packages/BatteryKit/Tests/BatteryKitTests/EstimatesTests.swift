import Foundation
import Testing

@testable import BatteryKit

struct EstimatesTests {
    private let onBattery = BatterySnapshot(percentage: 60, powerSource: .battery, chargeState: .discharging, timeRemaining: 3 * 3600)

    @Test func timeOnlyAppliesOnBatteryWithAReading() {
        #expect(Estimates(snapshot: onBattery, systemWatts: 20).appliesToTime)
        #expect(!Estimates(snapshot: onBattery, systemWatts: nil).appliesToTime)
        let charging = BatterySnapshot(percentage: 60, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 1800)
        #expect(!Estimates(snapshot: charging, systemWatts: 20).appliesToTime)
        #expect(Estimates(snapshot: charging, systemWatts: 20).timeGained(byQuitting: 5) == 0)
    }

    @Test func slicesShareTheTimeThereWouldBeWithoutThem() {
        let estimates = Estimates(snapshot: onBattery, systemWatts: 20)
        // 5 W of 20 W costs an hour; 3 h + 1 h = 4 h, so the slice is a quarter of the battery.
        let shares = estimates.sliceShares(forAppsDrawing: [5])
        #expect(abs(shares[0] - 0.25) < 0.0001)
    }

    @Test func onTheAdapterSlicesAreShareOfPower() {
        let charged = BatterySnapshot(percentage: 100, powerSource: .powerAdapter, chargeState: .charged, timeRemaining: nil)
        let shares = Estimates(snapshot: charged, systemWatts: 10).sliceShares(forAppsDrawing: [2, 50])
        #expect(abs(shares[0] - 0.2) < 0.0001)
        #expect(shares[1] == TimeEstimate.maximumShare)
        #expect(Estimates(snapshot: charged, systemWatts: nil).sliceShares(forAppsDrawing: [2]) == [0])
    }
}

struct LowBatteryAlertTests {
    private func battery(_ percentage: Int, charging: Bool = false) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: charging ? .powerAdapter : .battery,
            chargeState: charging ? .charging : .discharging, timeRemaining: nil)
    }

    @Test func eachLevelFiresOnceOnTheWayDown() {
        var alert = LowBatteryAlert()
        let levels = [20, 10]
        #expect(alert.update(with: battery(25), levels: levels) == nil)
        #expect(alert.update(with: battery(20), levels: levels) == 20)
        #expect(alert.update(with: battery(19), levels: levels) == nil)
        #expect(alert.update(with: battery(10), levels: levels) == 10)
        #expect(alert.update(with: battery(9), levels: levels) == nil)
    }

    @Test func pluggingInRearms() {
        var alert = LowBatteryAlert()
        #expect(alert.update(with: battery(15), levels: [20]) == 20)
        #expect(alert.update(with: battery(16, charging: true), levels: [20]) == nil)
        #expect(alert.update(with: battery(15), levels: [20]) == 20)
    }

    @Test func aBigDropGivesOneNotificationForTheLowestLevel() {
        var alert = LowBatteryAlert()
        #expect(alert.update(with: battery(8), levels: [20, 10]) == 10)
        #expect(alert.update(with: battery(7), levels: [20, 10]) == nil)
    }
}
