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
        // The battery is running down on the adapter, with nothing known about why: not blamed on the charger's size.
        let draining = ChargingNote.evaluate(
            snapshot: pluggedIn(50, .notCharging), adapter: nil, systemWatts: nil, readings: BatteryReadings(current: -1.2))
        #expect(draining == .notGettingFullPower(adapterWatts: nil, chargerWatts: nil))
    }

    @Test func aBigChargerIsNeverCalledTooWeakForALightLoad() {
        // 0.4.3 said "about 6.6 W, more than the 100 W charger gives": running down at 6.6 W is the charger, cable or
        // port not giving its power, not the charger being too small.
        let note = ChargingNote.evaluate(
            snapshot: pluggedIn(95, .notCharging), adapter: PowerAdapter(watts: 100), systemWatts: 6.6,
            readings: BatteryReadings(temperature: 33, voltage: 12.65, current: -2.25))
        #expect(note == .notGettingFullPower(adapterWatts: 100, chargerWatts: nil))
        // With what comes in measured, that's said too.
        let measured = ChargingNote.evaluate(
            snapshot: pluggedIn(60, .notCharging), adapter: PowerAdapter(watts: 100), systemWatts: 25, chargerWatts: 15, readings: nil)
        #expect(measured == .notGettingFullPower(adapterWatts: 100, chargerWatts: 15))
    }

    @Test func whatComesInOutweighsAStrayCurrentReading() {
        // The charger covers everything the Mac draws, so a current reading saying otherwise is a moment out of date.
        let covered = ChargingNote.evaluate(
            snapshot: pluggedIn(95, .notCharging), adapter: PowerAdapter(watts: 100), systemWatts: 6.6, chargerWatts: 6.5,
            readings: BatteryReadings(current: -2.25))
        #expect(covered == .restingNearTarget(target: 100))
        // And a shortfall shows even when the current reading hasn't caught up.
        let short = ChargingNote.evaluate(
            snapshot: pluggedIn(60, .notCharging), adapter: PowerAdapter(watts: 30), systemWatts: 32, chargerWatts: 28,
            readings: BatteryReadings(current: 0))
        #expect(short == .adapterTooWeak(adapterWatts: 30, systemWatts: 32))
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

    @Test func restingNearFullWinsOverABusyOrWarmMac() {
        // A small charger and a busy Mac at 97%: macOS isn't topping up yet, and the charger isn't to blame.
        let busy = ChargingNote.evaluate(
            snapshot: pluggedIn(97, .notCharging), adapter: PowerAdapter(watts: 30), systemWatts: 28,
            readings: BatteryReadings(temperature: 41, current: 0))
        #expect(busy == .restingNearTarget(target: 100))
        // But a battery running down on the adapter is the charger, even near full.
        let draining = ChargingNote.evaluate(
            snapshot: pluggedIn(97, .notCharging), adapter: PowerAdapter(watts: 30), systemWatts: 33, readings: BatteryReadings(current: -0.8))
        #expect(draining == .adapterTooWeak(adapterWatts: 30, systemWatts: 33))
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

    // MARK: - Resting

    @Test func aHeldBatteryBreathesSlowlyAndSmoothly() {
        // Full brightness at the start and end of a breath, deepest where breathing out turns to breathing in.
        #expect(Breathing.dimming(at: 0) == 0)
        #expect(Breathing.dimming(at: 1) < 0.0001)
        let deepest = Breathing.exhale / Breathing.duration
        #expect(abs(Breathing.dimming(at: deepest) - 1) < 0.0001)
        // Breathing out is quicker than breathing back in.
        #expect(Breathing.exhale < Breathing.inhale)
        // No jumps: neighbouring frames are close, and the first and last barely move from still.
        let values = Breathing.phases.map(Breathing.dimming(at:))
        #expect(zip(values, values.dropFirst()).allSatisfy { abs($0 - $1) < 0.12 })
        #expect(values.first! < 0.05 && values.last! < 0.05)
        #expect(Breathing.depth >= 0.15 && Breathing.depth <= 0.3)
    }

    @Test func eachStateMovesTheWayItsStyleSays() {
        func motion(
            _ snapshot: BatterySnapshot, _ charging: ChargingMotionStyle = .flow, _ trickle: TrickleMotionStyle = .slowPulse,
            _ holding: HoldingMotionStyle = .breathing
        ) -> MenuBarMotion? {
            MenuBarMotion(snapshot: snapshot, charging: charging, trickle: trickle, holding: holding)
        }
        #expect(motion(pluggedIn(45, .charging)) == .flow(level: 0.45, target: 1))
        #expect(motion(pluggedIn(45, .charging), .liquid) == .liquid)
        #expect(motion(pluggedIn(45, .charging), .stripes) == .stripes)
        // The last few percent to the target, whatever the charging style.
        #expect(motion(pluggedIn(97, .charging), .liquid) == .slowPulse)
        #expect(motion(pluggedIn(77, .charging, target: 80), .flow, .calmLiquid) == .calmLiquid)
        #expect(motion(pluggedIn(80, .notCharging, target: 80), .flow, .slowPulse, .stillWater) == .stillWater)
        #expect(motion(pluggedIn(80, .notCharging), .flow, .slowPulse, .heartbeat) == .heartbeat)
        #expect(motion(pluggedIn(100, .charged)) == nil)
        #expect(motion(onBattery) == nil)
    }

    @Test func loopsAreSeamlessAndBurstsRest() {
        for loop in [MenuBarMotion.liquid, .stripes, .calmLiquid, .stillWater] {
            let cycle = loop.cycle
            #expect(cycle.rest == 0)
            #expect(cycle.phases.first == 0 && cycle.phases.last! < 1)
        }
        for burst in [MenuBarMotion.slowPulse, .heartbeat, .breathing] {
            let cycle = burst.cycle
            #expect(cycle.rest > 0)
            #expect(cycle.phases.first! > 0 && cycle.phases.last! < 1)
        }
        // A loop ends where it starts, so there's no jump from its last frame to its first.
        for y in stride(from: 0.0, through: 12, by: 1.5) {
            #expect(abs(LiquidSurface.charging(y: y, phase: 0) - LiquidSurface.charging(y: y, phase: 1)) < 1e-9)
            #expect(abs(LiquidSurface.calm(y: y, phase: 0) - LiquidSurface.calm(y: y, phase: 1)) < 1e-9)
            #expect(abs(LiquidSurface.still(y: y, height: 12, phase: 0) - LiquidSurface.still(y: y, height: 12, phase: 1)) < 1e-9)
        }
        #expect(Stripes.offset(at: 1) == Stripes.spacing)
    }

    @Test func theShapesStaySubtle() {
        let surface = stride(from: 0.0, through: 1, by: 0.01).flatMap { phase in
            stride(from: 0.0, through: 12, by: 0.5).map { LiquidSurface.charging(y: $0, phase: phase) }
        }
        #expect(surface.map(abs).max()! <= 1.5)
        #expect(EdgePulse.strength(at: 0) == 0 && abs(EdgePulse.strength(at: 0.5) - 1) < 1e-9)
        #expect(Heartbeat.swell(at: 0) == 0)
        #expect(Heartbeat.swell(at: 0.2) > 0.1)
        #expect(Heartbeat.swell(at: 1) == 0)
    }

    // MARK: - An app's processes

    @Test func helpersDropTheAppsName() {
        func short(_ name: String, in app: String) -> String {
            ProcessEnergy(pid: 1, name: name, watts: 0, isApp: false).shortName(inApp: app)
        }
        #expect(short("T3 Code (Nightly) Helper (Renderer)", in: "T3 Code (Nightly)") == "Helper (Renderer)")
        #expect(short("Google Chrome Helper (GPU)", in: "Google Chrome") == "Helper (GPU)")
        #expect(short("Xcode-Helper", in: "Xcode") == "Helper")
        // The app itself, another name, and a name that only starts like the app's keep theirs.
        #expect(short("T3 Code (Nightly)", in: "T3 Code (Nightly)") == "T3 Code (Nightly)")
        #expect(short("cloudflared", in: "T3 Code (Nightly)") == "cloudflared")
        #expect(short("SafariBookmarksSyncAgent", in: "Safari") == "SafariBookmarksSyncAgent")
        #expect(short("Safari", in: "") == "Safari")
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
        detector.willSleep()
        // macOS can announce the charger before it says the Mac woke.
        #expect(detector.update(pluggedIn(64, .charging), at: start.addingTimeInterval(3599)) == nil)
        #expect(detector.update(onBattery, at: start.addingTimeInterval(3599.5)) == nil)
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
