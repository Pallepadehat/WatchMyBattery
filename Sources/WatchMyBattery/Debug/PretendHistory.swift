#if DEBUG
    import BatteryKit
    import Foundation

    /// Months of made-up history, for working on Settings › History without waiting months for a real one:
    /// `--pretend-history`, or the preview renderer. Weekdays at a desk with a few apps that each keep their own
    /// hours, quieter weekends, a little drift from week to week, and charging every night.
    enum PretendHistory {
        private struct Habit {
            let app: BatteryHistory.AppIdentity
            /// Its draw while running, in watts.
            let watts: Double
            /// The hours of the day it runs, as a weight from 0 (never) to 1.
            let hours: (Int) -> Double
            /// Runs at weekends too.
            let weekends: Bool
        }

        private static let habits: [Habit] = [
            Habit(
                app: .init(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"), watts: 3.4,
                hours: { (9...12).contains($0) ? 1 : (13...17).contains($0) ? 0.8 : 0 }, weekends: false),
            Habit(
                app: .init(name: "Safari", bundleIdentifier: "com.apple.Safari"), watts: 1.3, hours: { (8...23).contains($0) ? 0.7 : 0 },
                weekends: true),
            Habit(
                app: .init(name: "Music", bundleIdentifier: "com.apple.Music"), watts: 0.9, hours: { (18...23).contains($0) ? 1 : 0.15 },
                weekends: true),
            Habit(
                app: .init(name: "Messages", bundleIdentifier: "com.apple.MobileSMS"), watts: 0.35, hours: { (8...22).contains($0) ? 0.6 : 0 },
                weekends: true),
            Habit(
                app: .init(name: "Mail", bundleIdentifier: "com.apple.mail"), watts: 0.4, hours: { (8...10).contains($0) ? 1 : 0.3 },
                weekends: false),
            Habit(
                app: .init(name: "Photos", bundleIdentifier: "com.apple.Photos"), watts: 2.2, hours: { (19...21).contains($0) ? 0.6 : 0 },
                weekends: true),
            Habit(
                app: .init(name: "Notes", bundleIdentifier: "com.apple.Notes"), watts: 0.2, hours: { (9...18).contains($0) ? 0.5 : 0 },
                weekends: false),
            Habit(
                app: .init(name: "Terminal", bundleIdentifier: "com.apple.Terminal"), watts: 0.6, hours: { (10...16).contains($0) ? 0.7 : 0 },
                weekends: false),
            Habit(
                app: .init(name: "Calendar", bundleIdentifier: "com.apple.iCal"), watts: 0.15, hours: { (8...9).contains($0) ? 1 : 0.1 },
                weekends: false),
            Habit(
                app: .init(name: "Preview", bundleIdentifier: "com.apple.Preview"), watts: 0.5, hours: { (14...16).contains($0) ? 0.5 : 0 },
                weekends: false),
        ]

        /// `days` of history ending now: the profile for all of them, and the last day in full.
        static func make(days: Int = 120, now: Date = Date()) -> (history: BatteryHistory, profile: UsageProfile) {
            var profile = UsageProfile(hours: [], apps: [:], lastLevel: nil, now: now, retention: 366 * 24 * 3600)
            var history = BatteryHistory()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            // The same made-up months every time.
            var random = SplitMix(seed: 2026)
            let dayStartOfHistory = now.addingTimeInterval(-BatteryHistory.retention)

            for offset in (0..<days).reversed() {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let weekend = calendar.isDateInWeekend(day)
                // Some days stay plugged in.
                guard random.next() > (weekend ? 0.45 : 0.12) else { continue }
                // Xcode slowly grows hungrier, so its trend shows.
                let drift = 1 + Double(days - offset) / Double(days) * 0.4
                let unplug = (weekend ? 10.0 : 8.0) + random.next() * 2
                let plugIn = min(unplug + (weekend ? 3 : 5) + random.next() * 5, 23.5)
                var level = 100
                var cursor = day.addingTimeInterval(unplug * 3600)
                let end = day.addingTimeInterval(plugIn * 3600)
                guard cursor < now else { continue }

                func recordLevel(_ percentage: Int, pluggedIn: Bool, at date: Date) {
                    let point = BatteryHistory.LevelPoint(date: date, percentage: percentage, isPluggedIn: pluggedIn)
                    profile.record(level: point)
                    if date >= dayStartOfHistory {
                        history.record(
                            BatterySnapshot(
                                percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery,
                                chargeState: pluggedIn ? .charging : .discharging, timeRemaining: nil), at: date)
                    }
                }

                recordLevel(100, pluggedIn: true, at: cursor.addingTimeInterval(-60))
                recordLevel(100, pluggedIn: false, at: cursor)
                var used = 0.0
                while cursor < end, cursor.addingTimeInterval(300) <= now {
                    let next = cursor.addingTimeInterval(300)
                    let hour = calendar.component(.hour, from: cursor)
                    var joules: [BatteryHistory.AppIdentity: Double] = [:]
                    for habit in habits where !weekend || habit.weekends {
                        let weight = habit.hours(hour) * (0.6 + random.next() * 0.8)
                        guard weight > 0.05 else { continue }
                        let watts = habit.watts * weight * (habit.app.name == "Xcode" ? drift : 1)
                        joules[habit.app] = watts * 300
                    }
                    let appWatts = joules.values.reduce(0, +) / 300
                    let systemWatts = 3 + appWatts
                    let sample = BatteryHistory.EnergySample(
                        date: next, seconds: 300, joules: Dictionary(uniqueKeysWithValues: joules.map { ($0.key.key, $0.value) }),
                        systemWatts: systemWatts)
                    let identities = Dictionary(uniqueKeysWithValues: joules.keys.map { ($0.key, $0) })
                    profile.record(sample, apps: identities)
                    if next >= dayStartOfHistory {
                        history.record(joules: joules, seconds: 300, systemWatts: systemWatts, at: next)
                    }
                    // A 100 Wh battery.
                    used += systemWatts * 300 / 3600 / 100 * 100
                    if Int(used) > 100 - level, level > 5 {
                        level = max(100 - Int(used), 5)
                        recordLevel(level, pluggedIn: false, at: next)
                    }
                    cursor = next
                }
                if cursor < now { recordLevel(level, pluggedIn: true, at: cursor) }
            }
            return (history, profile)
        }

        /// A tiny repeatable random number generator: 0..<1.
        /// Vitals to go with ``make(days:now:)``: on battery at a desk through the working day, warm while charging in the
        /// evening, resting on the charger at night, and a battery wearing a little as the cycles add up.
        static func makeVitals(days: Int = 120, now: Date = Date()) -> BatteryVitals {
            var vitals = BatteryVitals(retention: 366 * 24 * 3600, now: now)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            var random = SplitMix(seed: 4711)
            var level = 100.0
            for dayIndex in 0..<days {
                guard let day = calendar.date(byAdding: .day, value: dayIndex - days + 1, to: today) else { continue }
                let isWeekend = calendar.isDateInWeekend(day)
                let worn = Double(dayIndex) / Double(days)
                for hour in 0..<24 {
                    for minute in [5, 25, 45] {
                        guard let date = calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day), date <= now else { continue }
                        let onBattery = isWeekend ? (11...16).contains(hour) : (9...17).contains(hour)
                        let charging = !onBattery && level < 99
                        let busy = onBattery ? 6 + random.next() * (isWeekend ? 5 : 9) : 4 + random.next() * 3
                        let batteryWatts: Double
                        let charger: Double?
                        if onBattery {
                            batteryWatts = -busy
                            charger = nil
                            level = max(level - busy / 3, 8)
                        } else if charging {
                            let rate = level < 80 ? 45 + random.next() * 15 : 12 + random.next() * 6
                            batteryWatts = rate
                            charger = rate + busy
                            level = min(level + rate / 4.5, 100)
                        } else {
                            batteryWatts = 0
                            charger = busy
                        }
                        let temperature =
                            28 + (onBattery ? busy * 0.45 : 0) + (charging ? max(batteryWatts - 10, 0) * 0.17 : 0) + random.next() * 1.5
                            + (isWeekend ? -0.5 : 0)
                        let reading = VitalsReading(
                            temperature: temperature, voltage: 11.4 + level / 100 * 1.6 + (charging ? 0.15 : 0) - random.next() * 0.05,
                            batteryWatts: batteryWatts, systemWatts: busy, chargerWatts: charger, percentage: Int(level.rounded()),
                            isPluggedIn: !onBattery)
                        vitals.record(reading, at: date, calendar: calendar)
                    }
                }
                let health = BatteryHealth(
                    condition: .normal, maximumCapacity: ((0.97 - worn * 0.03) * 100).rounded() / 100, cycleCount: 212 + dayIndex * 7 / 10)
                vitals.record(health: health, at: day.addingTimeInterval(9 * 3600), calendar: calendar)
            }
            return vitals
        }

        private struct SplitMix {
            var state: UInt64
            init(seed: UInt64) { state = seed }
            mutating func next() -> Double {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
            }
        }
    }
#endif
