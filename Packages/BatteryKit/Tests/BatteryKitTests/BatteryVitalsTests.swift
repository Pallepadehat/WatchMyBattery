import Foundation
import Testing

@testable import BatteryKit

struct BatteryVitalsTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Midnight on a Monday, in Copenhagen.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))! }
    private func at(day: Int, hour: Double) -> Date { monday.addingTimeInterval(Double(day) * 24 * 3600 + hour * 3600) }

    @Test func statsKeepTheRangeAndAverage() {
        var stats = ReadingStats([30, 34, 32])
        #expect(stats.mean == 32)
        #expect(stats.low == 30)
        #expect(stats.high == 34)
        stats.add(nil)
        stats.add(.nan)
        #expect(stats.count == 3)
        var other = ReadingStats([40])
        other.merge(stats)
        #expect(other.count == 4)
        #expect(other.low == 30)
        #expect(other.high == 40)
        #expect(ReadingStats().mean == nil)
    }

    @Test func statsSurviveEncoding() throws {
        let stats = ReadingStats([1, 2])
        let data = try JSONEncoder().encode(stats)
        #expect(try JSONDecoder().decode(ReadingStats.self, from: data) == stats)
        let empty = try JSONEncoder().encode(ReadingStats())
        #expect(try JSONDecoder().decode(ReadingStats.self, from: empty) == ReadingStats())
    }

    @Test func readingsGoIntoTheirHour() {
        var vitals = BatteryVitals(retention: 30 * 24 * 3600, now: monday)
        vitals.record(VitalsReading(temperature: 30, voltage: 12.5, batteryWatts: -8, systemWatts: 8), at: at(day: 0, hour: 9.1), calendar: calendar)
        vitals.record(VitalsReading(temperature: 40, voltage: 12.3, batteryWatts: -12, systemWatts: 12), at: at(day: 0, hour: 9.5), calendar: calendar)
        vitals.record(
            VitalsReading(temperature: 35, voltage: 12.9, batteryWatts: 30, systemWatts: 10, chargerWatts: 40, isPluggedIn: true),
            at: at(day: 0, hour: 10.2), calendar: calendar)
        #expect(vitals.hours.count == 2)
        let nine = vitals.hours[0]
        #expect(nine.start == at(day: 0, hour: 9))
        #expect(nine.readings == 2)
        #expect(nine.pluggedIn.isEmpty)
        #expect(nine.all.temperature.mean == 35)
        #expect(nine.all.discharging.high == 12)
        #expect(nine.all.charging.isEmpty)
        #expect(nine.all.warm == 1)
        let ten = vitals.hours[1]
        #expect(ten.pluggedIn.charging.mean == 30)
        #expect(ten.all.charger.mean == 40)
        #expect(ten.pluggedIn.readings == 1)
        #expect(ten.onBattery.isEmpty)
    }

    @Test func aReadingFromAnEarlierHourGoesInOrder() {
        var vitals = BatteryVitals(retention: 30 * 24 * 3600, now: monday)
        vitals.record(VitalsReading(temperature: 30), at: at(day: 0, hour: 11), calendar: calendar)
        vitals.record(VitalsReading(temperature: 31), at: at(day: 0, hour: 9), calendar: calendar)
        #expect(vitals.hours.map(\.start) == [at(day: 0, hour: 9), at(day: 0, hour: 11)])
    }

    @Test func oldHoursGoButHealthStays() {
        var vitals = BatteryVitals(retention: 2 * 24 * 3600, now: monday)
        vitals.record(VitalsReading(temperature: 30), at: at(day: 0, hour: 1), calendar: calendar)
        vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.95, cycleCount: 100), at: at(day: 0, hour: 1), calendar: calendar)
        vitals.record(VitalsReading(temperature: 30), at: at(day: 5, hour: 1), calendar: calendar)
        #expect(vitals.hours.count == 1)
        #expect(vitals.health.count == 1)
    }

    @Test func healthIsOneEntryADay() {
        var vitals = BatteryVitals(now: monday)
        #expect(
            vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.95, cycleCount: 100), at: at(day: 0, hour: 9), calendar: calendar) != nil)
        #expect(
            vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.95, cycleCount: 100), at: at(day: 0, hour: 15), calendar: calendar) == nil)
        #expect(
            vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.94, cycleCount: 101), at: at(day: 0, hour: 20), calendar: calendar) != nil)
        #expect(vitals.health.count == 1)
        #expect(vitals.health[0].cycleCount == 101)
        #expect(
            vitals.record(health: BatteryHealth(condition: .normal, maximumCapacity: nil, cycleCount: nil), at: at(day: 1, hour: 9), calendar: calendar) == nil)
    }

    @Test func reportsAddHoursUpToDays() {
        var vitals = BatteryVitals(retention: 30 * 24 * 3600, now: monday)
        for day in 0..<3 {
            for hour in [9.0, 14, 20] {
                vitals.record(VitalsReading(temperature: 30 + Double(day), systemWatts: 10), at: at(day: day, hour: hour), calendar: calendar)
            }
        }
        let report = vitals.report(from: monday, to: at(day: 7, hour: 0), granularity: .day, calendar: calendar)
        #expect(report.periods.count == 7)
        #expect(report.periods[0].stats.readings == 3)
        #expect(report.periods[1].stats.temperature.mean == 31)
        #expect(report.periods[3].isEmpty)
        #expect(report.whole.stats.readings == 9)
        #expect(report.whole.stats.temperature.low == 30)
        #expect(report.whole.stats.temperature.high == 32)
        #expect(report.whole.coveredSeconds == 9 * 3600)

        let hourly = vitals.report(from: monday, to: at(day: 1, hour: 0), granularity: .hour, calendar: calendar)
        #expect(hourly.periods.count == 24)
        #expect(hourly.periods[9].stats.readings == 1)
    }

    @Test func theFilterKeepsBatteryAndChargerApart() {
        var vitals = BatteryVitals(retention: 30 * 24 * 3600, now: monday)
        for hour in [9.0, 10, 11] {
            vitals.record(VitalsReading(temperature: 30, systemWatts: 8), at: at(day: 0, hour: hour), calendar: calendar)
        }
        for hour in [9.5, 20, 21] {
            vitals.record(VitalsReading(temperature: 38, systemWatts: 6, isPluggedIn: true), at: at(day: 0, hour: hour), calendar: calendar)
        }
        let end = at(day: 1, hour: 0)
        let all = vitals.report(from: monday, to: end, granularity: .day, calendar: calendar)
        let battery = vitals.report(from: monday, to: end, granularity: .day, filter: .onBattery, calendar: calendar)
        let charger = vitals.report(from: monday, to: end, granularity: .day, filter: .pluggedIn, calendar: calendar)
        #expect(all.whole.stats.readings == 6)
        #expect(battery.whole.stats.temperature.mean == 30)
        #expect(charger.whole.stats.temperature.mean == 38)
        #expect(battery.whole.warmSeconds == 0)
        // 9:00 was half plugged in and warm, and 20:00 and 21:00 wholly.
        #expect(charger.whole.warmSeconds == 1800 + 2 * 3600)
        // Time on the charger is the same whatever's shown.
        #expect(battery.pluggedInShare == 0.5)
        #expect(charger.pluggedInShare == 0.5)
    }

    @Test func hoursOfTheDayAddUpOverDays() {
        var vitals = BatteryVitals(retention: 30 * 24 * 3600, now: monday)
        for day in 0..<7 {
            for hour in 0..<24 {
                let warm = hour == 15 ? 6.0 : 0
                vitals.record(VitalsReading(temperature: 30 + warm), at: at(day: day, hour: Double(hour) + 0.5), calendar: calendar)
            }
        }
        let report = vitals.report(from: monday, to: at(day: 7, hour: 0), granularity: .day, calendar: calendar)
        #expect(report.hoursOfDay.count == 24)
        #expect(report.hoursOfDay[15].stats.readings == 7)
        #expect(report.hoursOfDay[15].stats.temperature.mean == 36)
        #expect(report.warmestHour == 15)
        #expect(report.busiestHour == nil)
    }

    @Test func noHourIsWarmestWhenTheDayIsEven() {
        var vitals = BatteryVitals(retention: 30 * 24 * 3600, now: monday)
        for hour in 0..<24 { vitals.record(VitalsReading(temperature: 30), at: at(day: 0, hour: Double(hour)), calendar: calendar) }
        #expect(vitals.report(from: monday, to: at(day: 1, hour: 0), granularity: .hour, calendar: calendar).warmestHour == nil)
    }

    @Test func healthChangeIsAgainstTheDayBefore() {
        var vitals = BatteryVitals(now: monday)
        vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.96, cycleCount: 100), at: at(day: 0, hour: 9), calendar: calendar)
        vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.95, cycleCount: 104), at: at(day: 3, hour: 9), calendar: calendar)
        vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.94, cycleCount: 110), at: at(day: 6, hour: 9), calendar: calendar)
        let report = vitals.report(from: at(day: 2, hour: 0), to: at(day: 7, hour: 0), granularity: .day, calendar: calendar)
        #expect(report.health.count == 2)
        #expect(abs((report.capacityChange ?? 0) - -0.02) < 0.0001)
        #expect(report.cyclesAdded == 10)
    }

    @Test func exportsAnHourARow() {
        var vitals = BatteryVitals(retention: 30 * 24 * 3600, now: monday)
        vitals.record(VitalsReading(temperature: 31.25, voltage: 12.4, systemWatts: 9, percentage: 80), at: at(day: 0, hour: 9), calendar: calendar)
        vitals.record(VitalsReading(temperature: 33), at: at(day: 0, hour: 10), calendar: calendar)
        vitals.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.9, cycleCount: 300), at: at(day: 0, hour: 9), calendar: calendar)
        let lines = HistoryExport.vitalsCSV(vitals, calendar: calendar).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("hour_start,readings,temperature_avg_c"))
        let first = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(first[2] == "31.3" || first[2] == "31.2")
        #expect(first.suffix(2) == ["90.0", "300"])
        // The day's health goes on its first hour only.
        #expect(lines[2].hasSuffix(",,"))
        #expect(HistoryExport.suggestedFileName(.vitalsCSV, now: monday).contains("Battery Vitals"))
    }

    @MainActor @Test func theStoreKeepsWhatWasRecorded() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "vitals-\(UUID().uuidString).store")
        defer { HistoryStore.removeFiles(at: url) }
        let now = Date()
        do {
            let store = try VitalsStore(url: url, now: now)
            store.record(VitalsReading(temperature: 31, voltage: 12.4, systemWatts: 9), at: now)
            store.record(VitalsReading(temperature: 33), at: now)
            store.record(health: BatteryHealth(condition: nil, maximumCapacity: 0.9, cycleCount: 300), at: now)
            try store.save()
        }
        let reopened = try VitalsStore(url: url, now: now)
        #expect(reopened.vitals.hours.count == 1)
        #expect(reopened.vitals.hours[0].readings == 2)
        #expect(reopened.vitals.hours[0].all.temperature.mean == 32)
        #expect(reopened.vitals.health.first?.cycleCount == 300)
        reopened.removeAll()
        try reopened.save()
        #expect(try VitalsStore(url: url, now: now).vitals.isEmpty)
    }
}
