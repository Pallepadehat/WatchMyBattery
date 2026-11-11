import Foundation

/// Spots apps that keep using a lot of power, for the runaway app notification.
///
/// It's fed the same samples history keeps (one every few minutes, on
/// battery). An app is a runaway once its average power over the last
/// ``window`` reaches ``threshold``. Each app is reported once, and again
/// only after it has calmed down to half the threshold, or the Mac was
/// plugged in.
public struct RunawayDetector: Sendable, Equatable {
    /// Average watts that count as a lot.
    public var threshold: Double
    /// How long an app has to keep it up.
    public var window: TimeInterval

    private var samples: [BatteryHistory.EnergySample] = []
    /// Apps already reported, until they calm down.
    public private(set) var reported: Set<String> = []

    public init(threshold: Double = 4, window: TimeInterval = 15 * 60) {
        self.threshold = threshold
        self.window = window
    }

    /// Feeds in a sample; returns the keys of apps that just became runaways, hungriest first.
    public mutating func add(_ sample: BatteryHistory.EnergySample) -> [String] {
        samples.append(sample)
        // Keep just enough to cover the window: drop the oldest while the rest still do.
        while samples.count > 1, samples.dropFirst().reduce(0, { $0 + $1.seconds }) >= window {
            samples.removeFirst()
        }
        let covered = samples.reduce(0) { $0 + $1.seconds }
        // A gap (the Mac slept, or was plugged in) breaks the run.
        let isContinuous = zip(samples, samples.dropFirst()).allSatisfy { abs($1.start.timeIntervalSince($0.date)) < 60 }
        guard isContinuous else {
            samples = [sample]
            return []
        }

        var average: [String: Double] = [:]
        for sample in samples {
            for (key, joules) in sample.joules { average[key, default: 0] += joules / covered }
        }
        // Calm again: may be reported next time.
        reported = reported.filter { (average[$0] ?? 0) >= threshold / 2 }
        guard covered >= window * 0.95 else { return [] }

        let runaways = average.filter { $0.value >= threshold && !reported.contains($0.key) }
            .sorted { $0.value > $1.value }
            .map(\.key)
        reported.formUnion(runaways)
        return runaways
    }

    /// Average watts of an app over the samples held, for the notification's wording.
    public func averageWatts(of key: String) -> Double? {
        let covered = samples.reduce(0) { $0 + $1.seconds }
        guard covered > 0 else { return nil }
        return samples.reduce(0) { $0 + ($1.joules[key] ?? 0) } / covered
    }

    /// Lets an app be reported again on the next sample: it was in use when it was due, so it wasn't.
    public mutating func forget(_ key: String) {
        reported.remove(key)
    }

    /// Plugged in: start over, so every app can be reported again next time.
    public mutating func reset() {
        samples = []
        reported = []
    }
}
