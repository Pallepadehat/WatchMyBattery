import Foundation
import Testing

@testable import BatteryKit

/// 0.5.1: apps as a share of the battery, and the time on the charger.
struct StatsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000 - 800_000_000.truncatingRemainder(dividingBy: 3600))

    private func hour(_ index: Int, drained: Int, battery: Double = 3600, measured: Double = 3600, watts: Double = 10) -> UsageProfile.Hour {
        UsageProfile.Hour(
            start: start.addingTimeInterval(Double(index) * 3600), batterySeconds: battery, drained: drained, sampledSeconds: measured,
            systemJoules: watts * measured, measuredSeconds: measured, appJoules: [:])
    }

    // MARK: - Battery use

    @Test func aRateComesFromTheMeasuredHours() throws {
        // A 72 Wh battery at 10 W: 10 Wh an hour is about 14 points.
        let profile = UsageProfile(hours: (0..<4).map { hour($0, drained: 14) }, apps: [:], lastLevel: nil, now: start.addingTimeInterval(5 * 3600))
        let rate = try #require(profile.pointsPerJoule)
        #expect(abs(rate - 14 / 36_000) < 1e-9)
        // An app that used 5 W for an hour used about 7% of the battery.
        #expect(abs(try #require(BatteryUse.points(joules: 5 * 3600, rate: rate)) - 7) < 0.01)
    }

    @Test func hoursAsleepCountForTheirMeasuredPart() throws {
        // Asleep most of the hour: measured for six minutes, so only a tenth of its drain counts against those joules.
        let hours = [hour(0, drained: 14), hour(1, drained: 14), hour(2, drained: 10, measured: 360)]
        let profile = UsageProfile(hours: hours, apps: [:], lastLevel: nil, now: start.addingTimeInterval(4 * 3600))
        let rate = try #require(profile.pointsPerJoule)
        #expect(abs(rate - 29 / (72_000 + 3_600.0)) < 1e-9)
    }

    @Test func tooLittleHistoryHasNoRate() {
        #expect(UsageProfile().pointsPerJoule == nil)
        let short = UsageProfile(hours: [hour(0, drained: 2)], apps: [:], lastLevel: nil, now: start.addingTimeInterval(3600))
        #expect(short.pointsPerJoule == nil)
        #expect(BatteryUse.points(joules: 100, rate: nil) == nil)
    }

    @Test func anImplausibleRateIsHeldInRange() throws {
        // 90 points for 1 Wh would be a 1 Wh battery.
        let profile = UsageProfile(
            hours: [hour(0, drained: 90, watts: 1)], apps: [:], lastLevel: nil, now: start.addingTimeInterval(3600))
        #expect(try #require(profile.pointsPerJoule) == UsageProfile.plausibleRate.upperBound)
    }

    // MARK: - Time on the charger

    @Test func readingsAddUpToTimeOnTheCharger() {
        var vitals = BatteryVitals(retention: 365 * 24 * 3600, now: start)
        let calendar = Calendar(identifier: .gregorian)
        // An hour: 3 readings on battery, 4 charging, then it reaches 80% and holds for 5.
        var readings: [VitalsReading] = Array(repeating: VitalsReading(percentage: 50), count: 3)
        readings += Array(repeating: VitalsReading(percentage: 70, isPluggedIn: true), count: 4)
        readings.append(VitalsReading(percentage: 80, isPluggedIn: true, isHolding: true, reachedLimit: true))
        readings += Array(repeating: VitalsReading(percentage: 80, isPluggedIn: true, isHolding: true), count: 4)
        for (index, reading) in readings.enumerated() {
            vitals.record(reading, at: start.addingTimeInterval(Double(index) * 300), calendar: calendar)
        }
        // The next hour, held full.
        for index in 0..<12 {
            vitals.record(
                VitalsReading(percentage: 100, isPluggedIn: true, isHolding: true), at: start.addingTimeInterval(3600 + Double(index) * 300),
                calendar: calendar)
        }
        let report = vitals.report(from: start, to: start.addingTimeInterval(2 * 3600), granularity: .day, calendar: calendar)
        let charge = report.whole.charge
        #expect(charge.onBattery == 900)
        #expect(charge.charging == 1200)
        #expect(charge.holding == 1500)
        #expect(charge.full == 3600)
        #expect(charge.limitReached == 1)
        #expect(charge.heldPerArrival == 5100)
        #expect(charge.pluggedIn == 6300)
    }

    @Test func aFewReadingsDontStandForTheWholeHour() {
        var vitals = BatteryVitals(retention: 365 * 24 * 3600, now: start)
        vitals.record(VitalsReading(percentage: 80, isPluggedIn: true, isHolding: true), at: start)
        let report = vitals.report(from: start, to: start.addingTimeInterval(3600), granularity: .day)
        #expect(report.whole.charge.holding == ChargeTime.readingInterval)
    }

    @Test func holdingNeedsTheCharger() {
        let reading = VitalsReading(percentage: 80, isPluggedIn: false, isHolding: true, reachedLimit: true)
        #expect(!reading.isHolding)
        #expect(!reading.reachedLimit)
    }

    @Test func hoursFromBeforeDontCountTowardTheCharger() throws {
        // As 0.5.0 saved them: no holding counts at all.
        var stats = VitalsStats()
        stats.add(VitalsReading(percentage: 80, isPluggedIn: true, isHolding: true))
        let data = try PropertyListEncoder().encode(stats)
        var plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        for key in ["holding", "holdingFull", "limitReached", "tracksHolding"] { plist[key] = nil }
        let old = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let decoded = try PropertyListDecoder().decode(VitalsStats.self, from: old)
        #expect(decoded.readings == 1)
        #expect(!decoded.tracksHolding)
        #expect(decoded.holding == 0)
        #expect(try PropertyListDecoder().decode(VitalsStats.self, from: data) == stats)

        var hour = BatteryVitals.Hour(start: start)
        hour.pluggedIn = decoded
        var time = ChargeTime()
        time.add(hour)
        #expect(time.isEmpty)
    }
}
