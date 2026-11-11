import Foundation
import Testing

@testable import BatteryKit

@Suite struct ChargingGlintTests {
    /// The menu bar battery's body is 23 points wide.
    private let body = 23.0

    /// The furthest the swell moves between two frames on screen.
    private func largestStep(of sweep: ChargingGlint, level: Double) -> Double {
        let all = (0...2000).map { Double($0) / 2000 }
        return zip(sweep.phases, sweep.phases.dropFirst()).map { from, to in
            let positions = all.filter { $0 >= from && $0 <= to }.map { ChargingGlint.frame(at: $0, bodyWidth: body, level: level).center }
            return (positions.max() ?? 0) - (positions.min() ?? 0)
        }.max() ?? 0
    }

    @Test(arguments: [0.05, 0.2, 0.45, 0.62, 0.8, 0.9, 0.97])
    func noVisibleFrameIsSkipped(level: Double) {
        let sweep = ChargingGlint(bodyWidth: body, level: level)
        let step = sweep.frameInterval / ChargingGlint.sweepDuration
        for (from, to) in zip(sweep.phases, sweep.phases.dropFirst()) {
            #expect(to - from <= step * 1.0001)
        }
    }

    /// Fewer frames than ever only where they'd have been wasted: the swell still moves a point at most.
    @Test(arguments: [0.7, 0.8, 0.9, 0.97])
    func aShorterSweepIsJustAsSmooth(level: Double) {
        let sweep = ChargingGlint(bodyWidth: body, level: level)
        #expect(sweep.frameInterval > 1.0 / 24)
        #expect(largestStep(of: sweep, level: level) <= ChargingGlint.maximumStep + 1e-9)
    }

    /// A long way to go keeps every frame it always had, and moves exactly as it always did.
    @Test(arguments: [0.05, 0.2, 0.45])
    func aLongSweepIsUnchanged(level: Double) {
        let sweep = ChargingGlint(bodyWidth: body, level: level)
        #expect(abs(sweep.frameInterval - 1.0 / 24) < 1e-12)
        #expect(sweep.phases.count == ChargingGlint.maximumFrames - 2)
    }

    @Test func aFullerBatteryNeedsFewerFrames() {
        let counts = [0.2, 0.62, 0.8, 0.9, 0.97].map { ChargingGlint(bodyWidth: body, level: $0).phases.count }
        #expect(counts == counts.sorted(by: >))
        #expect(counts.first! <= ChargingGlint.maximumFrames)
        #expect(counts.last! >= ChargingGlint.minimumFrames - 2)
        // A nearly full battery takes well under half the frames it used to.
        #expect(Double(ChargingGlint(bodyWidth: body, level: 0.9).phases.count) < Double(ChargingGlint.maximumFrames) * 0.5)
    }

    @Test func aSweepTakesAsLongAsItAlwaysHas() {
        for level in [0.1, 0.5, 0.95] {
            let sweep = ChargingGlint(bodyWidth: body, level: level)
            let frames = Int((ChargingGlint.sweepDuration / sweep.frameInterval).rounded()) + 1
            #expect(frames >= ChargingGlint.minimumFrames && frames <= ChargingGlint.maximumFrames)
        }
        #expect(abs(ChargingGlint(bodyWidth: body, level: 0.2).frameInterval - 1.0 / 24) < 1e-9)
    }

    @Test func framesThatLookLikeTheStillIconAreLeftOut() {
        let sweep = ChargingGlint(bodyWidth: body, level: 0.62)
        #expect(sweep.phases.first! > 0)
        #expect(sweep.phases.last! < 1)
        #expect(sweep.phases.allSatisfy { !ChargingGlint.frame(at: $0, bodyWidth: body, level: 0.62).isInvisible })
        #expect(ChargingGlint.frame(at: 0, bodyWidth: body, level: 0.62).isInvisible)
        #expect(ChargingGlint.frame(at: 1, bodyWidth: body, level: 0.62).isInvisible)
    }

    @Test func theSwellRunsFromTheChargeToTheTerminal() {
        let start = ChargingGlint.frame(at: 0, bodyWidth: body, level: 0.5)
        let end = ChargingGlint.frame(at: 1, bodyWidth: body, level: 0.5)
        #expect(start.center == 11.5)
        #expect(end.center == body + end.width / 2)
        // Brightest mid-way, and the terminal flashes as the swell gets there.
        #expect(ChargingGlint.frame(at: 0.5, bodyWidth: body, level: 0.5).strength == 1)
        #expect(ChargingGlint.frame(at: 0.3, bodyWidth: body, level: 0.5).flash == 0)
        #expect(ChargingGlint.frame(at: 0.775, bodyWidth: body, level: 0.5).flash > 0.99)
    }

    @Test func theFillMatchesTheIcon() {
        #expect(ChargingGlint.fillWidth(bodyWidth: body, level: 0) == 0)
        #expect(ChargingGlint.fillWidth(bodyWidth: body, level: 0.01) == 3)
        #expect(ChargingGlint.fillWidth(bodyWidth: body, level: 0.5) == 11.5)
        #expect(ChargingGlint.fillWidth(bodyWidth: body, level: 1) == body)
    }

    @Test func outOfRangePhasesAreClamped() {
        #expect(ChargingGlint.frame(at: -1, bodyWidth: body, level: 0.5) == ChargingGlint.frame(at: 0, bodyWidth: body, level: 0.5))
        #expect(ChargingGlint.frame(at: 2, bodyWidth: body, level: 0.5) == ChargingGlint.frame(at: 1, bodyWidth: body, level: 0.5))
    }
}

@Suite struct DisplayThresholdTests {
    private let threshold = DisplayThreshold.watts

    @Test func smallWigglesAreHeld() {
        #expect(!threshold.isVisible(from: 14, to: 14.2))
        #expect(!threshold.isVisible(from: 2.6, to: 2.64))
        #expect(!threshold.isVisible(from: 0.03, to: 0.035))
    }

    @Test func realChangesShow() {
        #expect(threshold.isVisible(from: 14, to: 14.4))
        #expect(threshold.isVisible(from: 2.6, to: 2.5))
        #expect(threshold.isVisible(from: 0.03, to: 0.05))
    }

    @Test func appearingAndDisappearingAlwaysShow() {
        #expect(threshold.isVisible(from: nil, to: 0.001))
        #expect(threshold.isVisible(from: 3, to: nil))
        #expect(!threshold.isVisible(from: nil, to: nil))
    }
}

@Suite struct IconPaletteTests {
    /// A flat icon, as premultiplied RGBA: `color` everywhere `isInside` says, transparent elsewhere.
    private func icon(side: Int = 24, color: (UInt8, UInt8, UInt8), alpha: UInt8 = 255, isInside: (Int, Int) -> Bool = { _, _ in true }) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side where isInside(x, y) {
                let index = (y * side + x) * 4
                let a = Double(alpha) / 255
                bytes[index] = UInt8((Double(color.0) * a).rounded())
                bytes[index + 1] = UInt8((Double(color.1) * a).rounded())
                bytes[index + 2] = UInt8((Double(color.2) * a).rounded())
                bytes[index + 3] = alpha
            }
        }
        return bytes
    }

    @Test func findsTheIconsColour() throws {
        let purple = try #require(IconPalette.dominantColor(rgba: icon(color: (140, 60, 220))))
        #expect(abs(purple.hue - 0.75) < 0.02)
        let red = try #require(IconPalette.dominantColor(rgba: icon(color: (230, 40, 40))))
        #expect(red.hue < 0.02 || red.hue > 0.98)
    }

    @Test func liftsItIntoAReadableRange() throws {
        let dull = try #require(IconPalette.dominantColor(rgba: icon(color: (80, 110, 60))))
        #expect((0.55...0.8).contains(dull.saturation))
        #expect((0.75...0.9).contains(dull.brightness))
        let loud = try #require(IconPalette.dominantColor(rgba: icon(color: (255, 0, 0))))
        #expect(loud.saturation == 0.8 && loud.brightness == 0.9)
    }

    @Test func greyAndWhiteIconsHaveNoColour() {
        #expect(IconPalette.dominantColor(rgba: icon(color: (128, 128, 128))) == nil)
        #expect(IconPalette.dominantColor(rgba: icon(color: (255, 255, 255))) == nil)
        #expect(IconPalette.dominantColor(rgba: [UInt8](repeating: 0, count: 24 * 24 * 4)) == nil)
    }

    @Test func aWhiteGlyphOnColourKeepsTheColour() throws {
        var bytes = icon(color: (30, 120, 240))
        // A white bar across the middle.
        for y in 8..<16 { for x in 0..<24 { for channel in 0..<4 { bytes[(y * 24 + x) * 4 + channel] = 255 } } }
        let color = try #require(IconPalette.dominantColor(rgba: bytes))
        #expect(abs(color.hue - 0.6) < 0.03)
    }

    @Test func translucentEdgesDontCount() {
        // Only a faint, mostly transparent tint: nothing reliable to go on.
        #expect(IconPalette.dominantColor(rgba: icon(color: (255, 0, 0), alpha: 100)) == nil)
    }

    @Test func huesMatchTheTextbook() {
        func hue(_ r: Double, _ g: Double, _ b: Double) -> Double { IconPalette.hsb(r, g, b).hue }
        #expect(hue(1, 0, 0) == 0)
        #expect(abs(hue(0, 1, 0) - 1.0 / 3) < 1e-12)
        #expect(abs(hue(0, 0, 1) - 2.0 / 3) < 1e-12)
        #expect(abs(hue(1, 0, 1) - 5.0 / 6) < 1e-12)
        let grey = IconPalette.hsb(0.5, 0.5, 0.5)
        #expect(grey.hue == 0 && grey.saturation == 0 && grey.brightness == 0.5)
        let black = IconPalette.hsb(0, 0, 0)
        #expect(black.hue == 0 && black.saturation == 0 && black.brightness == 0)
    }

    @Test func oddSizedBuffersAreReadSafely() {
        #expect(IconPalette.dominantColor(rgba: [255, 0, 0]) == nil)
        #expect(IconPalette.dominantColor(rgba: []) == nil)
    }
}

@Suite struct ChargeTargetTests {
    private let body = 23.0

    @Test func theSwellSettlesAtTheTarget() {
        let end = ChargingGlint.frame(at: 1, bodyWidth: body, level: 0.6, target: 0.8)
        #expect(abs(end.center - ChargingGlint.targetPosition(bodyWidth: body, target: 0.8)) < 1e-9)
        // And glows there as it arrives.
        #expect(ChargingGlint.frame(at: 0.775, bodyWidth: body, level: 0.6, target: 0.8).flash > 0.99)
    }

    @Test func chargingToFullIsAsItAlwaysWas() {
        for phase in stride(from: 0.0, through: 1, by: 0.05) {
            #expect(ChargingGlint.frame(at: phase, bodyWidth: body, level: 0.4, target: 1) == ChargingGlint.frame(at: phase, bodyWidth: body, level: 0.4))
        }
        #expect(ChargingGlint(bodyWidth: body, level: 0.4, target: 1).phases == ChargingGlint(bodyWidth: body, level: 0.4).phases)
    }

    @Test func aCloserTargetNeedsFewerFrames() {
        let toFull = ChargingGlint(bodyWidth: body, level: 0.6).phases.count
        let toEighty = ChargingGlint(bodyWidth: body, level: 0.6, target: 0.8).phases.count
        #expect(toEighty < toFull)
    }

    @Test func optimizedChargingSetsTheTarget() {
        let charging: [String: Any] = [
            "Current Capacity": 62, "Max Capacity": 100, "Power Source State": "AC Power", "Is Charging": true,
            PowerSourceReader.optimizedChargingKey: 1,
        ]
        let snapshot = PowerSourceReader.snapshot(from: charging, isLowPowerModeOn: false)
        #expect(snapshot.chargeTarget == 80)
        #expect(snapshot.hasChargeLimit)
        #expect(abs(snapshot.progressToTarget - 62.0 / 80) < 1e-12)
        #expect(!snapshot.isAtTarget)

        var held = charging
        held["Current Capacity"] = 80
        held["Is Charging"] = false
        let holding = PowerSourceReader.snapshot(from: held, isLowPowerModeOn: false)
        #expect(holding.chargeState == .notCharging)
        #expect(holding.isAtTarget)
        #expect(holding.progressToTarget == 1)
    }

    @Test func withoutOptimizedChargingItChargesToFull() {
        let snapshot = PowerSourceReader.snapshot(
            from: ["Current Capacity": 62, "Max Capacity": 100, "Power Source State": "AC Power", "Is Charging": true], isLowPowerModeOn: false)
        #expect(snapshot.chargeTarget == 100)
        #expect(!snapshot.hasChargeLimit)
        // On battery the flag means nothing: it's about charging.
        let onBattery = PowerSourceReader.snapshot(
            from: ["Current Capacity": 62, "Max Capacity": 100, "Power Source State": "Battery Power", PowerSourceReader.optimizedChargingKey: true],
            isLowPowerModeOn: false)
        #expect(onBattery.chargeTarget == 100)
    }

    @Test func targetsStayInRange() {
        #expect(BatterySnapshot(percentage: 50, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: nil, chargeTarget: 0).chargeTarget == 1)
        #expect(BatterySnapshot(percentage: 50, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: nil, chargeTarget: 150).chargeTarget == 100)
    }
}
