import Foundation

/// Smooths noisy power readings so the panel doesn't jitter from one sample
/// to the next.
///
/// Each value is an exponential moving average. Values that fall below
/// ``floor`` are dropped, so apps that go quiet leave the list.
public struct PowerSmoother<Key: Hashable & Sendable>: Sendable {
    /// How much a new reading counts, 0–1. Higher reacts faster.
    public var responsiveness: Double
    /// Below this, a value counts as zero and is forgotten.
    public var floor: Double

    public private(set) var values: [Key: Double] = [:]

    public init(responsiveness: Double = 0.35, floor: Double = 0.005) {
        self.responsiveness = responsiveness
        self.floor = floor
    }

    /// Folds in a new set of readings. Keys missing from `readings` count as zero.
    public mutating func add(_ readings: [Key: Double]) {
        var next: [Key: Double] = [:]
        next.reserveCapacity(max(values.count, readings.count))
        for key in Set(values.keys).union(readings.keys) {
            let reading = readings[key] ?? 0
            // The first reading for a key is taken as is, so new apps show up at once.
            let value = values[key].map { $0 + responsiveness * (reading - $0) } ?? reading
            if value >= floor { next[key] = value }
        }
        values = next
    }

    public mutating func removeValue(forKey key: Key) {
        values[key] = nil
    }

    public mutating func reset() {
        values = [:]
    }
}

/// Smooths a single reading, like the system's total power draw.
public struct SingleValueSmoother: Sendable {
    public var responsiveness: Double
    public private(set) var value: Double?

    public init(responsiveness: Double = 0.3) {
        self.responsiveness = responsiveness
    }

    public mutating func add(_ reading: Double) {
        value = value.map { $0 + responsiveness * (reading - $0) } ?? reading
    }

    public mutating func reset() {
        value = nil
    }
}
