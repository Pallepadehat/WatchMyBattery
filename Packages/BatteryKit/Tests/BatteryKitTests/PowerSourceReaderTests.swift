import Foundation
import IOKit.ps
import Testing

@testable import BatteryKit

@Suite struct PowerSourceReaderTests {
    @Test func dischargingUsesTimeToEmpty() {
        let snapshot = PowerSourceReader.snapshot(
            from: [
                kIOPSCurrentCapacityKey: 64, kIOPSMaxCapacityKey: 100,
                kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
                kIOPSIsChargingKey: false, kIOPSTimeToEmptyKey: 290,
            ], isLowPowerModeOn: false)
        #expect(snapshot.percentage == 64)
        #expect(snapshot.chargeState == .discharging)
        #expect(snapshot.powerSource == .battery)
        #expect(snapshot.timeRemaining == TimeInterval(290 * 60))
    }

    @Test func chargingUsesTimeToFull() {
        let snapshot = PowerSourceReader.snapshot(
            from: [
                kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 100,
                kIOPSPowerSourceStateKey: kIOPSACPowerValue,
                kIOPSIsChargingKey: true, kIOPSTimeToFullChargeKey: 75,
            ], isLowPowerModeOn: false)
        #expect(snapshot.chargeState == .charging)
        #expect(snapshot.timeRemaining == TimeInterval(75 * 60))
    }

    @Test func calculatingHasNoEstimate() {
        let snapshot = PowerSourceReader.snapshot(
            from: [
                kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100,
                kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue, kIOPSTimeToEmptyKey: -1,
            ], isLowPowerModeOn: false)
        #expect(snapshot.timeRemaining == nil)
    }

    @Test func pluggedInAndHoldingIsNotCharging() {
        let snapshot = PowerSourceReader.snapshot(
            from: [
                kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100,
                kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false,
            ], isLowPowerModeOn: false)
        #expect(snapshot.chargeState == .notCharging)
        #expect(snapshot.timeRemaining == nil)
    }

    @Test func pluggedInAndFullIsCharged() {
        let snapshot = PowerSourceReader.snapshot(
            from: [
                kIOPSCurrentCapacityKey: 100, kIOPSMaxCapacityKey: 100,
                kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false, kIOPSIsChargedKey: true,
            ], isLowPowerModeOn: false)
        #expect(snapshot.chargeState == .charged)
    }
}
