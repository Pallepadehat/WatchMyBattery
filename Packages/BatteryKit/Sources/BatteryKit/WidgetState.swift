import Foundation

/// What the app hands its widgets: the battery, the apps using the most, the accessories and the forecast, written to
/// the app group's container as JSON whenever any of it changes enough to show. The widgets read the battery's level
/// straight from macOS too, so it's never older than the widget; the rest comes from here.
public struct WidgetState: Codable, Sendable, Equatable {
    public struct Battery: Codable, Sendable, Equatable {
        public var percentage: Int
        public var isPluggedIn: Bool
        public var isCharging: Bool
        public var isLowPowerModeOn: Bool
        /// Until empty, or until full while charging; `nil` while macOS works it out.
        public var timeRemaining: TimeInterval?
        /// Where charging stops: a charge limit or Optimized Battery Charging's 80%.
        public var chargeTarget: Int

        public init(
            percentage: Int, isPluggedIn: Bool, isCharging: Bool, isLowPowerModeOn: Bool, timeRemaining: TimeInterval?, chargeTarget: Int
        ) {
            self.percentage = percentage
            self.isPluggedIn = isPluggedIn
            self.isCharging = isCharging
            self.isLowPowerModeOn = isLowPowerModeOn
            self.timeRemaining = timeRemaining
            self.chargeTarget = chargeTarget
        }

        public init(_ snapshot: BatterySnapshot) {
            self.init(
                percentage: snapshot.percentage, isPluggedIn: snapshot.isPluggedIn, isCharging: snapshot.isCharging,
                isLowPowerModeOn: snapshot.isLowPowerModeOn, timeRemaining: snapshot.timeRemaining, chargeTarget: snapshot.chargeTarget)
        }
    }

    /// An app among the ones that used the most battery lately.
    public struct App: Codable, Sendable, Equatable, Identifiable {
        public var key: String
        public var name: String
        public var bundleIdentifier: String?
        /// Its share of what the apps used, 0–1.
        public var share: Double
        /// The battery time it cost; `nil` without power readings.
        public var batteryTime: TimeInterval?
        /// Its icon, a PNG next to the state file, by file name.
        public var iconFile: String?
        /// The colour the panel gives its slice, from its icon, as sRGB red, green and blue (0–1).
        public var tint: [Double]?

        public var id: String { key }

        public init(
            key: String, name: String, bundleIdentifier: String?, share: Double, batteryTime: TimeInterval?, iconFile: String?,
            tint: [Double]? = nil
        ) {
            self.key = key
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.share = share
            self.batteryTime = batteryTime
            self.iconFile = iconFile
            self.tint = tint
        }
    }

    /// An accessory with a battery, and its parts.
    public struct Accessory: Codable, Sendable, Equatable, Identifiable {
        public struct Part: Codable, Sendable, Equatable {
            /// "left", "right", "both", "single" or "case".
            public var role: String
            public var percentage: Int
            public var isCharging: Bool

            public init(role: String, percentage: Int, isCharging: Bool) {
                self.role = role
                self.percentage = percentage
                self.isCharging = isCharging
            }
        }

        public var id: String
        public var name: String
        /// An SF Symbol for it, chosen by the app, which knows the models.
        public var symbol: String
        public var parts: [Part]

        public init(id: String, name: String, symbol: String, parts: [Part]) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.parts = parts
        }

        /// The lowest battery in it: what to show when there's room for one number.
        public var lowest: Int? { parts.filter { $0.role != "case" }.map(\.percentage).min() ?? parts.map(\.percentage).min() }
    }

    /// The forecast's line and when it reaches the low level, while on battery.
    public struct Forecast: Codable, Sendable, Equatable {
        public var points: [Point]
        public var reachesLow: Date?
        public var runsOut: Date?
        public var lowLevel: Int

        public struct Point: Codable, Sendable, Equatable {
            public var date: Date
            public var percentage: Double

            public init(date: Date, percentage: Double) {
                self.date = date
                self.percentage = percentage
            }
        }

        public init(points: [Point], reachesLow: Date?, runsOut: Date?, lowLevel: Int) {
            self.points = points
            self.reachesLow = reachesLow
            self.runsOut = runsOut
            self.lowLevel = lowLevel
        }

        public init(_ forecast: BatteryForecast) {
            self.init(
                points: forecast.points.map { Point(date: $0.date, percentage: $0.percentage) }, reachesLow: forecast.reachesLow,
                runsOut: forecast.runsOut, lowLevel: forecast.lowLevel)
        }

        /// The level expected at `date`, between the points either side; `nil` past the end of the line.
        public func percentage(at date: Date) -> Double? {
            guard let first = points.first, date >= first.date else { return points.first?.percentage }
            for (before, after) in zip(points, points.dropFirst()) where date <= after.date {
                let span = after.date.timeIntervalSince(before.date)
                guard span > 0 else { return after.percentage }
                let share = date.timeIntervalSince(before.date) / span
                return before.percentage + (after.percentage - before.percentage) * share
            }
            return nil
        }
    }

    /// A level a half hour, over the last 24 hours, for the widget's little chart.
    public struct Level: Codable, Sendable, Equatable {
        public var start: Date
        public var percentage: Int
        public var isPluggedIn: Bool

        public init(start: Date, percentage: Int, isPluggedIn: Bool) {
            self.start = start
            self.percentage = percentage
            self.isPluggedIn = isPluggedIn
        }
    }

    public var updatedAt: Date
    public var battery: Battery?
    public var apps: [App]
    public var accessories: [Accessory]
    public var forecast: Forecast?
    public var levels: [Level]
    /// Battery used today, in percentage points, and time on battery.
    public var usedToday: Int?
    public var batteryTimeToday: TimeInterval?
    /// Low Power Mode can be switched (it can't on some Macs).
    public var canSwitchLowPowerMode: Bool

    public init(
        updatedAt: Date = Date(), battery: Battery?, apps: [App] = [], accessories: [Accessory] = [], forecast: Forecast? = nil,
        levels: [Level] = [], usedToday: Int? = nil, batteryTimeToday: TimeInterval? = nil, canSwitchLowPowerMode: Bool = true
    ) {
        self.updatedAt = updatedAt
        self.battery = battery
        self.apps = apps
        self.accessories = accessories
        self.forecast = forecast
        self.levels = levels
        self.usedToday = usedToday
        self.batteryTimeToday = batteryTimeToday
        self.canSwitchLowPowerMode = canSwitchLowPowerMode
    }

    /// The file's name in the container.
    public static let fileName = "WidgetState.json"

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> WidgetState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetState.self, from: data)
    }

    /// Whether this differs from `other` enough for the widgets to redraw: the level, the state, the apps or
    /// accessories, or the forecast's times. The time left moving by a minute isn't reason enough on its own.
    public func differsVisibly(from other: WidgetState?) -> Bool {
        guard let other else { return true }
        func minutes(_ value: TimeInterval?) -> Int? { value.map { Int($0 / 600) } }  // ten-minute steps
        let a = battery
        let b = other.battery
        if a?.percentage != b?.percentage || a?.isPluggedIn != b?.isPluggedIn || a?.isCharging != b?.isCharging
            || a?.isLowPowerModeOn != b?.isLowPowerModeOn || a?.chargeTarget != b?.chargeTarget
            || minutes(a?.timeRemaining) != minutes(b?.timeRemaining)
        {
            return true
        }
        if apps.map(\.key) != other.apps.map(\.key) || accessories != other.accessories { return true }
        if forecast?.reachesLow != other.forecast?.reachesLow || forecast?.runsOut != other.forecast?.runsOut { return true }
        return usedToday != other.usedToday || canSwitchLowPowerMode != other.canSwitchLowPowerMode
    }
}

/// The Darwin notifications the widgets and controls send the app, which is unsandboxed and can do what they can't
/// (Low Power Mode goes through its helper). A sandboxed extension may post these, without a payload, so each value
/// has a name of its own.
public enum WidgetCommand: String, CaseIterable, Sendable {
    case lowPowerModeOn = "com.pallepadehat.WatchMyBattery.lowPowerMode.on"
    case lowPowerModeOff = "com.pallepadehat.WatchMyBattery.lowPowerMode.off"
    /// The widgets would like fresh state (a widget was just added, say).
    case refresh = "com.pallepadehat.WatchMyBattery.refresh"

    public func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue as CFString), nil, nil, true)
    }
}
