import Foundation
import Testing

@testable import BatteryKit

@Suite struct GaugeLayoutTests {
    @Test func slicesAreSharesOfTheCharge() {
        // 50% of 400 is 200; a 30% share of that is 60.
        let layout = GaugeLayout(width: 400, level: 0.5, shares: [0.3], minimumSliceWidth: 10, minimumBaseWidth: 20)
        #expect(layout.sliceWidths == [60])
        #expect(layout.baseWidth == 140)
        #expect(layout.fillWidth == 200)
    }

    @Test func smallSharesGetTheMinimumWidth() {
        let layout = GaugeLayout(width: 400, level: 1, shares: [0.001], minimumSliceWidth: 34, minimumBaseWidth: 20)
        #expect(layout.sliceWidths == [34])
        #expect(layout.fillWidth == 400)
    }

    @Test func aLowBatteryStillShowsTheApps() {
        let layout = GaugeLayout(width: 300, level: 0.05, shares: [0.1, 0.1], minimumSliceWidth: 30, minimumBaseWidth: 6)
        #expect(layout.baseWidth == 6)
        #expect(layout.sliceWidths == [30, 30])
    }

    @Test func theFillFollowsTheLevelWhenTheAppsFit() {
        let layout = GaugeLayout(width: 300, level: 0.4, shares: [0.01, 0.01], minimumSliceWidth: 30, minimumBaseWidth: 6)
        #expect(layout.fillWidth == 120)
    }

    @Test func slicesThatDontFitAreLeftOut() {
        let layout = GaugeLayout(width: 150, level: 1, shares: [0.1, 0.1, 0.1, 0.1], minimumSliceWidth: 40, minimumBaseWidth: 60)
        #expect(layout.sliceWidths.count == 2)
        #expect(layout.fillWidth <= 150)
    }

    @Test func offsetsFollowTheBase() {
        let layout = GaugeLayout(width: 400, level: 1, shares: [0.1, 0.2], minimumSliceWidth: 10, minimumBaseWidth: 20)
        #expect(layout.sliceOffsets == [280, 320])
    }

    @Test func neverWiderThanTheBattery() {
        for level in stride(from: 0.0, through: 1.0, by: 0.05) {
            let layout = GaugeLayout(width: 288, level: level, shares: [0.4, 0.3, 0.2, 0.1, 0.05, 0.01])
            #expect(layout.fillWidth <= 288.0001)
        }
    }

    @Test func roomIsKeptForTheLabel() {
        let layout = GaugeLayout(width: 200, level: 1, shares: [0.1, 0.1, 0.1, 0.1], minimumSliceWidth: 40, labelWidth: 80)
        #expect(layout.sliceWidths.count == 3)
    }
}
