import Foundation

/// Decides when headphones have just connected, which is when the AirPods card slides in.
///
/// Whatever is connected when the app starts doesn't count: the card is for
/// the moment you put your AirPods in, not for launching the app. Earbuds
/// that drop out and come back within ``cooldown`` (which Bluetooth does
/// now and then, and so does taking one earbud out) don't count either.
public struct AccessoryArrivals: Sendable {
    /// Headphones connected at the last update; `nil` before the first one.
    private var connected: Set<String>?
    /// When each one was last seen going away.
    private var departures: [String: Date] = [:]
    public var cooldown: TimeInterval

    public init(cooldown: TimeInterval = 60) {
        self.cooldown = cooldown
    }

    /// Feeds in the accessories now connected; returns the headphones that just arrived.
    public mutating func update(with accessories: [Accessory], at now: Date = Date()) -> [Accessory] {
        // Only the case is no reason for a card: the earbuds are still in it.
        let headphones = accessories.filter { $0.kind.isAudio && $0.parts.contains { $0.role != .case } }
        let ids = Set(headphones.map(\.id))
        defer { connected = ids }
        guard let previous = connected else { return [] }

        for gone in previous.subtracting(ids) { departures[gone] = now }
        return headphones.filter { accessory in
            guard !previous.contains(accessory.id) else { return false }
            guard let departed = departures[accessory.id] else { return true }
            return now.timeIntervalSince(departed) >= cooldown
        }
    }
}

/// Decides when an accessory's battery has run low enough for a notification.
///
/// Each accessory is notified about once, when its lowest earbud (or its only
/// battery) reaches the threshold. Charging it, or its level climbing back
/// clearly above the threshold, re-arms it. The case doesn't count, as it's
/// there to charge the earbuds.
public struct AccessoryLowBatteryAlert: Sendable, Equatable {
    /// Accessories already notified about, until they charge.
    public private(set) var notified: Set<String> = []
    /// How far above the threshold the level has to climb before another
    /// notification, so a reading that wobbles around it doesn't notify twice.
    public static let rearmMargin = 5

    public init() {}

    /// Feeds in the accessories now connected; returns those that just ran low.
    public mutating func update(with accessories: [Accessory], threshold: Int) -> [Accessory] {
        var low: [Accessory] = []
        for accessory in accessories {
            guard let level = accessory.lowestLevel else { continue }
            if accessory.isChargingInUse || level > threshold + Self.rearmMargin {
                notified.remove(accessory.id)
            } else if level <= threshold, !notified.contains(accessory.id) {
                notified.insert(accessory.id)
                low.append(accessory)
            }
        }
        return low
    }
}
