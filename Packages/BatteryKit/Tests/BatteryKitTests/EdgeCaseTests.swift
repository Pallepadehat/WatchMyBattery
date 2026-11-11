import Foundation
import Testing

@testable import BatteryKit

/// What happens at the edges: odd readings from IOKit, a Mac without a battery, nothing to show.
@Suite struct EdgeCaseTests {
    @Test func snapshotsKeepTheLevelInRange() {
        #expect(BatterySnapshot(percentage: 140, powerSource: .powerAdapter, chargeState: .charged, timeRemaining: nil).percentage == 100)
        #expect(BatterySnapshot(percentage: -5, powerSource: .battery, chargeState: .discharging, timeRemaining: nil).percentage == 0)
        #expect(BatterySnapshot(percentage: 37, powerSource: .battery, chargeState: .discharging, timeRemaining: nil).level == 0.37)
    }

    @Test func noBatteryLooksPluggedInAndFull() {
        let snapshot = BatterySnapshot.noBattery
        #expect(!snapshot.hasBattery)
        #expect(snapshot.isPluggedIn)
        #expect(!snapshot.isCharging)
    }

    @Test func aMacWithoutABatteryRecordsNothing() {
        var history = BatteryHistory()
        history.record(.noBattery)
        #expect(history.isEmpty)
        #expect(history.sinceUnplugged(.noBattery) == nil)
    }

    @Test func aZeroMaximumCapacityReadsAsEmpty() {
        let snapshot = PowerSourceReader.snapshot(
            from: ["Current Capacity": 50, "Max Capacity": 0, "Power Source State": "Battery Power"], isLowPowerModeOn: false)
        #expect(snapshot.percentage == 0)
    }

    @Test func estimatesWithoutPowerShareNothing() {
        let snapshot = BatterySnapshot(percentage: 50, powerSource: .battery, chargeState: .discharging, timeRemaining: 3600)
        let estimates = Estimates(snapshot: snapshot, systemWatts: 0)
        #expect(estimates.share(of: 3) == 0)
        #expect(estimates.timeGained(byQuitting: 3) == 0)
        #expect(estimates.sliceShares(forAppsDrawing: []).isEmpty)
        #expect(Estimates(snapshot: snapshot, systemWatts: nil).sliceShares(forAppsDrawing: [1, 2]) == [0, 0])
    }

    @Test func aGaugeWithNoRoomHasNoSlices() {
        let layout = GaugeLayout(width: 0, level: 0.5, shares: [0.5, 0.2])
        #expect(layout.sliceWidths.isEmpty)
        #expect(layout.fillWidth <= 0)
        let negative = GaugeLayout(width: -20, level: 2, shares: [-1])
        #expect(negative.sliceWidths.isEmpty)
    }

    @Test func theAlertIgnoresAMacWithoutABattery() {
        var alert = LowBatteryAlert()
        #expect(alert.update(with: .noBattery, levels: [20, 10]) == nil)
        #expect(alert.notified.isEmpty)
    }

    @Test func theRunawayDetectorNeedsAWholeWindow() {
        var detector = RunawayDetector(threshold: 1, window: 600)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(detector.averageWatts(of: "anything") == nil)
        // 5 minutes at 10 W is a lot, but not for long enough.
        let sample = BatteryHistory.EnergySample(date: start + 300, seconds: 300, joules: ["hog": 3000], systemWatts: 12)
        #expect(detector.add(sample).isEmpty)
        #expect(detector.averageWatts(of: "hog") == 10)
    }

    @Test func formattingSurvivesHugeTimes() {
        #expect(TimeFormat.clock(1e9) == "277777:47")
        #expect(TimeFormat.compact(59) == "1m")
        #expect(TimeFormat.compact(29) == "0m")
    }
}

@Suite struct ControlCenterBatteryTests {
    @Test func readsControlCentersFlags() {
        #expect(ControlCenterBattery.isShownInMenuBar(flags: 2) == true)
        #expect(ControlCenterBattery.isShownInMenuBar(flags: 18) == true)  // In the menu bar and in Control Center.
        #expect(ControlCenterBattery.isShownInMenuBar(flags: 8) == false)
        #expect(ControlCenterBattery.isShownInMenuBar(flags: 24) == false)  // Hidden from the menu bar, kept in Control Center.
    }

    @Test func unknownFlagsSayNothing() {
        #expect(ControlCenterBattery.isShownInMenuBar(flags: nil) == nil)
        #expect(ControlCenterBattery.isShownInMenuBar(flags: 0) == nil)
        #expect(ControlCenterBattery.isShownInMenuBar(flags: 16) == nil)
    }
}
