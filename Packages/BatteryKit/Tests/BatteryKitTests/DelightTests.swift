import Foundation
import Testing

@testable import BatteryKit

/// 0.4.0's delight: the charger, why charging pauses, the chime, and what the menu bar says.
@Suite struct DelightTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func pluggedIn(_ percentage: Int, _ state: BatterySnapshot.ChargeState, target: Int = 100) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: .powerAdapter, chargeState: state, timeRemaining: state == .charging ? 3600 : nil,
            chargeTarget: target)
    }

    private let onBattery = BatterySnapshot(percentage: 64, powerSource: .battery, chargeState: .discharging, timeRemaining: 5 * 3600)

    // MARK: - The charger

    @Test func theChargerComesWithItsWattsAndName() {
        let adapter = PowerAdapterReader.adapter(from: ["Watts": 96, "Name": " 96W USB-C Power Adapter ", "FamilyCode": -536_854_528])
        #expect(adapter == PowerAdapter(watts: 96, name: "96W USB-C Power Adapter"))
        #expect(PowerAdapterReader.adapter(from: ["Watts": 30]) == PowerAdapter(watts: 30))
    }

    @Test func onBatteryThereIsNoCharger() {
        // What macOS returns with nothing plugged in.
        #expect(PowerAdapterReader.adapter(from: ["FamilyCode": 0]) == nil)
        #expect(PowerAdapterReader.adapter(from: ["Watts": 0, "Name": ""]) == nil)
    }

    // MARK: - Why charging pauses

    @Test func aHotBatteryPausesCharging() {
        let note = ChargingNote.evaluate(
            snapshot: pluggedIn(60, .notCharging), adapter: PowerAdapter(watts: 96), systemWatts: 10,
            readings: BatteryReadings(temperature: 42, current: 0))
        #expect(note == .pausedWhileHot(temperature: 42))
        let charging = ChargingNote.evaluate(
            snapshot: pluggedIn(60, .charging), adapter: nil, systemWatts: nil, readings: BatteryReadings(temperature: 41))
        #expect(charging == .slowedByHeat(temperature: 41))
    }

    @Test func aWarmBatteryIsNothingToMention() {
        let note = ChargingNote.evaluate(
            snapshot: pluggedIn(60, .charging), adapter: PowerAdapter(watts: 96), systemWatts: 10, readings: BatteryReadings(temperature: 36))
        #expect(note == nil)
    }

    @Test func aWeakChargerIsNamed() {
        // The Mac takes more than the charger gives.
        let overloaded = ChargingNote.evaluate(
            snapshot: pluggedIn(50, .notCharging), adapter: PowerAdapter(watts: 30), systemWatts: 31, readings: nil)
        #expect(overloaded == .adapterTooWeak(adapterWatts: 30, systemWatts: 31))
        // The battery is running down on the adapter, even with nothing else known.
        let draining = ChargingNote.evaluate(
            snapshot: pluggedIn(50, .notCharging), adapter: nil, systemWatts: nil, readings: BatteryReadings(current: -1.2))
        #expect(draining == .adapterTooWeak(adapterWatts: nil, systemWatts: nil))
    }

    @Test func aBusyChargerChargesSlowly() {
        let slow = ChargingNote.evaluate(snapshot: pluggedIn(50, .charging), adapter: PowerAdapter(watts: 30), systemWatts: 24, readings: nil)
        #expect(slow == .chargingSlowly(adapterWatts: 30, systemWatts: 24))
        let fine = ChargingNote.evaluate(snapshot: pluggedIn(50, .charging), adapter: PowerAdapter(watts: 96), systemWatts: 24, readings: nil)
        #expect(fine == nil)
    }

    @Test func aNearlyFullBatteryRestsBeforeToppingUp() {
        let note = ChargingNote.evaluate(snapshot: pluggedIn(97, .notCharging), adapter: PowerAdapter(watts: 96), systemWatts: 8, readings: nil)
        #expect(note == .restingNearTarget(target: 100))
        // Just under a charge limit, too.
        let limited = pluggedIn(77, .charging).limited(to: 80)
        var resting = limited
        resting.chargeState = .notCharging
        #expect(ChargingNote.evaluate(snapshot: resting, adapter: nil, systemWatts: nil, readings: nil) == .restingNearTarget(target: 80))
    }

    @Test func aHoldAtTheTargetIsLeftToTheChargeBar() {
        let held = pluggedIn(80, .charged).limited(to: 80)
        #expect(ChargingNote.evaluate(snapshot: held, adapter: PowerAdapter(watts: 30), systemWatts: 40, readings: nil) == nil)
        let optimized = pluggedIn(80, .notCharging, target: 80)
        #expect(ChargingNote.evaluate(snapshot: optimized, adapter: nil, systemWatts: nil, readings: nil) == nil)
    }

    @Test func aPauseWithNoVisibleCauseSaysNothing() {
        let note = ChargingNote.evaluate(
            snapshot: pluggedIn(40, .notCharging), adapter: PowerAdapter(watts: 96), systemWatts: 12,
            readings: BatteryReadings(temperature: 30, current: 0))
        #expect(note == nil)
        #expect(ChargingNote.evaluate(snapshot: onBattery, adapter: nil, systemWatts: 40, readings: BatteryReadings(temperature: 45)) == nil)
        #expect(ChargingNote.evaluate(snapshot: .noBattery, adapter: PowerAdapter(watts: 30), systemWatts: 40, readings: nil) == nil)
    }

    // MARK: - The chime

    @Test func theChimeFollowsPluggingInAndUnplugging() {
        var detector = PowerChangeDetector()
        #expect(detector.update(onBattery, at: start) == nil)
        #expect(detector.update(pluggedIn(64, .charging), at: start.addingTimeInterval(10)) == .pluggedIn)
        #expect(detector.update(pluggedIn(65, .charging), at: start.addingTimeInterval(20)) == nil)
        #expect(detector.update(onBattery, at: start.addingTimeInterval(30)) == .unplugged)
    }

    @Test func theChimeIsQuietWhenTheAppOpens() {
        var detector = PowerChangeDetector()
        #expect(detector.update(pluggedIn(64, .charging), at: start) == nil)
    }

    @Test func aLooseCableDoesNotChatter() {
        var detector = PowerChangeDetector()
        _ = detector.update(onBattery, at: start)
        #expect(detector.update(pluggedIn(64, .charging), at: start.addingTimeInterval(1)) == .pluggedIn)
        #expect(detector.update(onBattery, at: start.addingTimeInterval(1.5)) == nil)
        #expect(detector.update(pluggedIn(64, .charging), at: start.addingTimeInterval(2)) == nil)
        #expect(detector.update(onBattery, at: start.addingTimeInterval(10)) == .unplugged)
    }

    @Test func whatChangedInSleepIsOldNews() {
        var detector = PowerChangeDetector()
        _ = detector.update(onBattery, at: start)
        detector.didWake(at: start.addingTimeInterval(3600))
        #expect(detector.update(pluggedIn(64, .charging), at: start.addingTimeInterval(3601)) == nil)
        #expect(detector.update(onBattery, at: start.addingTimeInterval(3700)) == .unplugged)
    }

    @Test func aMacWithoutABatteryNeverChimes() {
        var detector = PowerChangeDetector()
        #expect(detector.update(.noBattery, at: start) == nil)
        #expect(detector.update(onBattery, at: start.addingTimeInterval(10)) == nil)
    }

    @Test func theChimeIsGentleAndEndsInSilence() {
        for change in [PowerChange.pluggedIn, .unplugged] {
            let samples = ChimeSynth.samples(for: change)
            #expect(samples.count == Int(ChimeSynth.duration * Double(ChimeSynth.sampleRate)))
            let loudest = samples.map(abs).max() ?? 0
            #expect(abs(loudest - ChimeSynth.peak) < 0.001)
            #expect(samples.first == 0)
            #expect(samples.last == 0)
        }
        #expect(ChimeSynth.samples(for: .pluggedIn) != ChimeSynth.samples(for: .unplugged))
    }

    @Test func theChimeIsAPlayableWAV() {
        let wav = ChimeSynth.wav(for: .pluggedIn)
        #expect(wav.count == 44 + ChimeSynth.samples(for: .pluggedIn).count * 2)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(String(decoding: wav[36..<40], as: UTF8.self) == "data")
    }

    // MARK: - The menu bar's text

    @Test func theMenuBarShowsWhatWasChosen() {
        #expect(MenuBarReadout(label: .none, snapshot: onBattery, watts: 8) == nil)
        #expect(MenuBarReadout(label: .percentage, snapshot: onBattery, watts: nil) == .percentage(64))
        #expect(MenuBarReadout(label: .timeRemaining, snapshot: onBattery, watts: nil) == .time(5 * 3600))
        #expect(MenuBarReadout(label: .timeRemaining, snapshot: pluggedIn(40, .charging), watts: nil) == .time(3600))
        #expect(MenuBarReadout(label: .powerDraw, snapshot: onBattery, watts: 7.4) == .watts(7.4))
    }

    @Test func theMenuBarFallsBackToThePercentage() {
        // Full, or still calculating: no time to show.
        #expect(MenuBarReadout(label: .timeRemaining, snapshot: pluggedIn(100, .charged), watts: nil) == .percentage(100))
        var calculating = onBattery
        calculating.timeRemaining = nil
        #expect(MenuBarReadout(label: .timeRemaining, snapshot: calculating, watts: nil) == .percentage(64))
        #expect(MenuBarReadout(label: .powerDraw, snapshot: onBattery, watts: nil) == .percentage(64))
        #expect(MenuBarReadout(label: .powerDraw, snapshot: onBattery, watts: .nan) == .percentage(64))
    }

    @Test func aMacWithoutABatteryShowsOnlyItsPower() {
        #expect(MenuBarReadout(label: .percentage, snapshot: .noBattery, watts: nil) == nil)
        #expect(MenuBarReadout(label: .timeRemaining, snapshot: .noBattery, watts: nil) == nil)
        #expect(MenuBarReadout(label: .powerDraw, snapshot: .noBattery, watts: 21) == .watts(21))
    }

    @Test func wattsAreRoundedSensibly() {
        let english = Locale(identifier: "en_US")
        #expect(PowerFormat.watts(4.23, locale: english) == "4.2 W")
        #expect(PowerFormat.watts(9.96, locale: english) == "10 W")
        #expect(PowerFormat.watts(31.6, locale: english) == "32 W")
        #expect(PowerFormat.watts(-1, locale: english) == "0.0 W")
        #expect(PowerFormat.watts(4.23, locale: Locale(identifier: "da_DK")) == "4,2 W")
    }
}
