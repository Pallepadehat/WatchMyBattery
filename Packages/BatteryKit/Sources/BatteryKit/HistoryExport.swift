import Foundation

/// The history, written out for a spreadsheet (CSV) or a script (JSON).
///
/// CSV has one row per hour of the kept history (two weeks, or longer if chosen), which is what a spreadsheet
/// does well with; the apps' CSV has a row for each app on each day it used the battery. JSON has everything: the
/// hours, the last day's level readings and app samples, the sleeps, and the apps by name.
public enum HistoryExport {
    public enum Format: String, Sendable, CaseIterable, Identifiable {
        case csv
        /// A row for each app on each day.
        case appsCSV = "apps-csv"
        /// A row for each hour of the battery's vitals: temperature, voltage, power.
        case vitalsCSV = "vitals-csv"
        case json

        public var id: Self { self }
        public var fileExtension: String { self == .json ? "json" : "csv" }
    }

    public static func data(
        _ format: Format, history: BatteryHistory, profile: UsageProfile, sleeps: SleepLog, vitals: BatteryVitals = BatteryVitals(),
        now: Date = Date()
    ) throws -> Data {
        switch format {
        case .csv: Data(csv(profile: profile).utf8)
        case .appsCSV: Data(appsCSV(profile: profile).utf8)
        case .vitalsCSV: Data(vitalsCSV(vitals).utf8)
        case .json: try json(history: history, profile: profile, sleeps: sleeps, now: now)
        }
    }

    /// "WatchMyBattery History 2026-11-13.csv", or "WatchMyBattery Apps 2026-11-13.csv"
    public static func suggestedFileName(_ format: Format, now: Date = Date()) -> String {
        let day = now.formatted(.iso8601.year().month().day())
        let name =
            switch format {
            case .appsCSV: "Apps"
            case .vitalsCSV: "Battery Vitals"
            case .csv, .json: "History"
            }
        return "WatchMyBattery \(name) \(day).\(format.fileExtension)"
    }

    /// The vitals' hours, oldest first, then nothing else: health days have a column of their own, on the hour they
    /// were read in (the first of their day).
    public static func vitalsCSV(_ vitals: BatteryVitals, calendar: Calendar = .current) -> String {
        var lines = [
            [
                "hour_start", "readings", "temperature_avg_c", "temperature_min_c", "temperature_max_c", "voltage_avg_v", "voltage_min_v",
                "voltage_max_v", "charging_avg_w", "discharging_avg_w", "mac_draw_avg_w", "mac_draw_max_w", "charger_avg_w", "level_min_percent",
                "level_max_percent", "plugged_in_percent", "maximum_capacity_percent", "cycle_count",
            ].joined(separator: ",")
        ]
        var healthByDay = Dictionary(vitals.health.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        func value(_ number: Double?, _ digits: Int) -> String { number.map { Self.number($0, digits: digits) } ?? "" }
        for hour in vitals.hours {
            let day = calendar.startOfDay(for: hour.start)
            let health = healthByDay.removeValue(forKey: day)
            let all = hour.all
            let fields = [
                iso(hour.start), String(hour.readings),
                value(all.temperature.mean, 1), value(all.temperature.low, 1), value(all.temperature.high, 1),
                value(all.voltage.mean, 3), value(all.voltage.low, 3), value(all.voltage.high, 3),
                value(all.charging.mean, 2), value(all.discharging.mean, 2), value(all.system.mean, 2), value(all.system.high, 2),
                value(all.charger.mean, 2), value(all.level.low, 0), value(all.level.high, 0),
                value(hour.readings > 0 ? Double(hour.pluggedIn.readings) / Double(hour.readings) * 100 : nil, 0),
                value(health?.maximumCapacity.map { $0 * 100 }, 1), health?.cycleCount.map(String.init) ?? "",
            ]
            lines.append(fields.map(escaped).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - CSV

    /// The hours, oldest first. Energy in watt-hours, which is what a battery's capacity is measured in.
    public static func csv(profile: UsageProfile) -> String {
        var lines = [
            [
                "hour_start", "minutes_on_battery", "battery_used_percent", "average_watts", "measured_minutes", "top_apps_wh",
            ].joined(separator: ",")
        ]
        for hour in profile.hours {
            let apps = hour.appJoules.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(5)
                .map { key, joules in "\(profile.apps[key]?.identity.name ?? key): \(number(joules / 3600, digits: 2))" }
                .joined(separator: "; ")
            let fields = [
                iso(hour.start),
                number(hour.batterySeconds / 60, digits: 1),
                String(hour.drained),
                hour.averageWatts.map { number($0, digits: 2) } ?? "",
                number(hour.measuredSeconds / 60, digits: 1),
                apps,
            ]
            lines.append(fields.map(escaped).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Each app's energy each day, by `calendar`'s days, oldest day first and the hungriest app first within it. The
    /// share is of what all the apps used that day; battery minutes are at that day's average power draw, when known.
    public static func appsCSV(profile: UsageProfile, calendar: Calendar = .current) -> String {
        var lines = [
            ["day", "app", "bundle_identifier", "energy_wh", "share_percent", "battery_minutes"].joined(separator: ",")
        ]
        guard let first = profile.hours.first?.start, let last = profile.hours.last?.start else { return lines[0] + "\n" }
        let report = profile.report(from: first, to: last.addingTimeInterval(3600), granularity: .day, calendar: calendar)
        // The day as the calendar has it, not as it is in UTC.
        let dayFormat = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        for period in report.periods where period.appJoules > 0 {
            let day = profile.report(from: period.start, to: period.end, granularity: .day, calendar: calendar)
            for app in day.apps {
                let fields = [
                    period.start.formatted(dayFormat),
                    app.app.name,
                    app.app.bundleIdentifier ?? "",
                    number(app.joules / 3600, digits: 3),
                    number(app.share * 100, digits: 1),
                    app.batteryTime.map { number($0 / 60, digits: 1) } ?? "",
                ]
                lines.append(fields.map(escaped).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quoted when it has to be, as RFC 4180 has it.
    static func escaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Always with a full stop, whatever the language: a spreadsheet in any locale reads it as a number.
    private static func number(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    // MARK: - JSON

    private struct Document: Encodable {
        struct Level: Encodable {
            let date: Date
            let percent: Int
            let pluggedIn: Bool
        }
        struct Sample: Encodable {
            let date: Date
            let seconds: Double
            let systemWatts: Double?
            let appJoules: [String: Double]
        }
        struct Hour: Encodable {
            let start: Date
            let secondsOnBattery: Double
            let batteryUsedPercent: Int
            let averageWatts: Double?
            let measuredSeconds: Double
            let appJoules: [String: Double]
        }
        struct App: Encodable {
            let key: String
            let name: String
            let bundleIdentifier: String?
            let firstSeen: Date
            let lastSeen: Date
        }
        struct Sleep: Encodable {
            let start: Date
            let end: Date
            let startPercent: Int
            let endPercent: Int
            let pluggedIn: Bool
            let percentPerHour: Double?
        }

        let exported: Date
        let format = "WatchMyBattery history, version 1"
        let apps: [App]
        let hours: [Hour]
        let levels: [Level]
        let samples: [Sample]
        let sleeps: [Sleep]
    }

    public static func json(history: BatteryHistory, profile: UsageProfile, sleeps: SleepLog, now: Date = Date()) throws -> Data {
        var apps = profile.apps.map { key, app in
            Document.App(
                key: key, name: app.identity.name, bundleIdentifier: app.identity.bundleIdentifier, firstSeen: app.firstSeen,
                lastSeen: app.lastSeen)
        }
        // Apps in the last day's samples that the hours haven't got to yet.
        for (key, identity) in history.apps where profile.apps[key] == nil {
            apps.append(Document.App(key: key, name: identity.name, bundleIdentifier: identity.bundleIdentifier, firstSeen: now, lastSeen: now))
        }
        let document = Document(
            exported: now,
            apps: apps.sorted { $0.key < $1.key },
            hours: profile.hours.map {
                .init(
                    start: $0.start, secondsOnBattery: $0.batterySeconds, batteryUsedPercent: $0.drained, averageWatts: $0.averageWatts,
                    measuredSeconds: $0.measuredSeconds, appJoules: $0.appJoules)
            },
            levels: history.levels.map { .init(date: $0.date, percent: $0.percentage, pluggedIn: $0.isPluggedIn) },
            samples: history.samples.map { .init(date: $0.date, seconds: $0.seconds, systemWatts: $0.systemWatts, appJoules: $0.joules) },
            sleeps: sleeps.sessions.map {
                .init(
                    start: $0.start, end: $0.end, startPercent: $0.startLevel, endPercent: $0.endLevel, pluggedIn: $0.wasPluggedIn,
                    percentPerHour: $0.perHour)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}
