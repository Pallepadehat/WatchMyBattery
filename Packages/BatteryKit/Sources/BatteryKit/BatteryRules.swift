import Foundation

/// "When the battery drops to 20%, turn on Low Power Mode and quit Docker": something to do, by itself, when the
/// battery or the charger changes. Made in Settings › Rules, saved as JSON.
public struct BatteryRule: Codable, Sendable, Hashable, Identifiable {
    /// What sets a rule off.
    public enum Trigger: Codable, Sendable, Hashable {
        /// The battery runs down to this level (on battery).
        case dropsTo(Int)
        /// The battery charges up to this level (plugged in).
        case chargesTo(Int)
        /// The charger is connected.
        case pluggedIn
        /// The charger is disconnected.
        case unplugged

        /// The level in it, for the ones that have one.
        public var level: Int? {
            switch self {
            case .dropsTo(let level), .chargesTo(let level): level
            case .pluggedIn, .unplugged: nil
            }
        }

        /// The same trigger at another level.
        public func with(level: Int) -> Trigger {
            switch self {
            case .dropsTo: .dropsTo(level)
            case .chargesTo: .chargesTo(level)
            case .pluggedIn, .unplugged: self
            }
        }
    }

    /// What a rule does.
    public enum Action: Codable, Sendable, Hashable {
        /// Turns Low Power Mode on, or off.
        case lowPowerMode(Bool)
        /// Asks these apps (by bundle identifier) to quit, as quitting them from the Dock would.
        case quitApps([String])
        /// Runs a shortcut from the Shortcuts app, by name.
        case runShortcut(String)
        /// Sends a notification saying the rule ran, and what it did.
        case notify
        /// Sets the charge limit to this level (80, say), or turns it off with 100.
        case chargeLimit(Int)
    }

    public var id: UUID
    public var isEnabled: Bool
    public var trigger: Trigger
    public var actions: [Action]

    public init(id: UUID = UUID(), isEnabled: Bool = true, trigger: Trigger, actions: [Action]) {
        self.id = id
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.actions = actions
    }

    /// Levels a rule can be set to.
    public static let levelChoices = [5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 100]

    /// Rules to start from, offered in Settings when there are none.
    public static let suggestions: [BatteryRule] = [
        BatteryRule(isEnabled: true, trigger: .dropsTo(20), actions: [.lowPowerMode(true)]),
        BatteryRule(isEnabled: true, trigger: .pluggedIn, actions: [.lowPowerMode(false)]),
    ]

    /// Saved as JSON in the preferences.
    public static func encode(_ rules: [BatteryRule]) -> Data? { try? JSONEncoder().encode(rules) }
    public static func decode(_ data: Data?) -> [BatteryRule] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([BatteryRule].self, from: data)) ?? []
    }
}

/// Decides which rules to run, from one battery reading to the next. It only ever fires on a change it saw happen:
/// a rule for 20% doesn't run when the app opens at 15%, or when a rule is made below its level. A level rule runs once
/// on the way down (or up), and again only after the battery has gone back past its level by ``rearmMargin``, so a
/// reading wobbling between 20% and 21% doesn't set it off again and again.
public struct RuleEngine: Sendable {
    private var last: BatterySnapshot?
    /// Level rules that have run, by ID, until the battery goes back the other way.
    public private(set) var spent: Set<UUID> = []
    private var lastPowerChange: Date?

    /// Going back past a rule's level by this many points sets it again.
    public static let rearmMargin = 3
    /// The charger connecting and disconnecting faster than this is a loose cable, not a change: only the first counts.
    public static let powerDebounce: TimeInterval = 5

    public init() {}

    /// The rules to run now, in the order given. Call it with every new reading.
    public mutating func update(with snapshot: BatterySnapshot, rules: [BatteryRule], at now: Date = Date()) -> [BatteryRule] {
        defer { last = snapshot }
        guard snapshot.hasBattery else { return [] }
        let active = rules.filter(\.isEnabled)
        rearm(for: snapshot, rules: active)
        guard let last else {
            // The first reading: rules already past their level count as run, so they wait for the battery to come back.
            for rule in active where Self.isPast(rule.trigger, snapshot) { spent.insert(rule.id) }
            return []
        }

        var fired: [BatteryRule] = []
        let powerChanged = last.isPluggedIn != snapshot.isPluggedIn
        let debounced = powerChanged && lastPowerChange.map { now.timeIntervalSince($0) < Self.powerDebounce } == true
        if powerChanged { lastPowerChange = now }
        for rule in active {
            switch rule.trigger {
            case .pluggedIn:
                if powerChanged, snapshot.isPluggedIn, !debounced { fired.append(rule) }
            case .unplugged:
                if powerChanged, !snapshot.isPluggedIn, !debounced { fired.append(rule) }
            case .dropsTo, .chargesTo:
                guard !spent.contains(rule.id), Self.isPast(rule.trigger, snapshot) else { continue }
                spent.insert(rule.id)
                fired.append(rule)
            }
        }
        return fired
    }

    /// A rule was made or changed: it shouldn't run just because the battery is already past its new level.
    public mutating func didChange(_ rule: BatteryRule) {
        spent.remove(rule.id)
        if let last, Self.isPast(rule.trigger, last) { spent.insert(rule.id) }
    }

    /// The battery has gone back the other way, far enough: level rules can run again.
    private mutating func rearm(for snapshot: BatterySnapshot, rules: [BatteryRule]) {
        guard !spent.isEmpty else { return }
        for rule in rules where spent.contains(rule.id) {
            switch rule.trigger {
            case .dropsTo(let level):
                if snapshot.percentage >= level + Self.rearmMargin { spent.remove(rule.id) }
            case .chargesTo(let level):
                if snapshot.percentage <= level - Self.rearmMargin { spent.remove(rule.id) }
            case .pluggedIn, .unplugged:
                spent.remove(rule.id)
            }
        }
        // Rules that were removed.
        spent.formIntersection(rules.map(\.id))
    }

    /// The battery is at or past a level rule's level, the way the rule goes.
    static func isPast(_ trigger: BatteryRule.Trigger, _ snapshot: BatterySnapshot) -> Bool {
        switch trigger {
        case .dropsTo(let level): !snapshot.isPluggedIn && snapshot.percentage <= level
        case .chargesTo(let level): snapshot.isPluggedIn && snapshot.percentage >= level
        case .pluggedIn, .unplugged: false
        }
    }
}
