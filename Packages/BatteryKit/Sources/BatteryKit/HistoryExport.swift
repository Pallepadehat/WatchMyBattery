import Foundation

/// The history, written out for a spreadsheet (CSV) or a script (JSON).
///
/// CSV has one row per hour of the kept history (two weeks, or longer if chosen), which is what a spreadsheet
/// does well with. JSON has everything: the hours, the last day's level readings and app samples, the sleeps, and
/// the apps by name.
public enum HistoryExport {
    public enum Format: String, Sendable, CaseIterable, Identifiable {
        case csv
        case json

        public var id: Self { self }
        public var fileExtension: String { rawValue }
    }

    public static func data(
        _ format: Format, history: BatteryHistory, profile: UsageProfile, sleeps: SleepLog, now: Date = Date()
    ) throws -> Data {
        switch format {
        case .csv: Data(csv(profile: profile).utf8)
        case .json: try json(history: history, profile: profile, sleeps: sleeps, now: now)
        }
    }

    /// "WatchMyBattery History 2026-11-13.csv"
    public static func suggestedFileName(_ format: Format, now: Date = Date()) -> String {
        let day = now.formatted(.iso8601.year().month().day())
        return "WatchMyBattery History \(day).\(format.fileExtension)"
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
