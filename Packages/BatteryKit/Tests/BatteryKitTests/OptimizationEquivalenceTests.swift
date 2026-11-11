import Foundation
import Testing

@testable import BatteryKit

/// The faster history and smoother have to give exactly the answers the simple versions gave. These hold them
/// against straightforward reference versions (the code as it was before 0.2.2) on many made-up days.
@Suite struct OptimizationEquivalenceTests {
    private static let seeds: [UInt64] = Array(1...40)
    private static let apps = (0..<25).map { BatteryHistory.AppIdentity(name: "App \($0)", bundleIdentifier: $0 % 4 == 0 ? nil : "com.example.\($0)") }

    /// A day or two of random readings, with gaps, charges and the odd sample dated out of order.
    private static func randomHistory(seed: UInt64) -> (history: BatteryHistory, end: Date) {
        var random = SplitMix64(seed: seed)
        var history = BatteryHistory()
        var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var percentage = 80
        var pluggedIn = false
        for _ in 0..<random.next(in: 50...600) {
            date += Double(random.next(in: 1...900))
            if random.next(in: 0...30) == 0 { pluggedIn.toggle() }
            percentage = min(max(percentage + (pluggedIn ? random.next(in: 0...3) : -random.next(in: 0...2)), 0), 100)
            history.record(snapshot(percentage, pluggedIn: pluggedIn), at: date)
            if !pluggedIn, random.next(in: 0...2) == 0 {
                var joules: [BatteryHistory.AppIdentity: Double] = [:]
                for _ in 0..<random.next(in: 0...20) { joules[apps[random.next(in: 0...(apps.count - 1))]] = Double(random.next(in: 0...400)) / 4 }
                // Now and then a sample from a clock that went back a little.
                let sampleDate = random.next(in: 0...25) == 0 ? date - Double(random.next(in: 1...600)) : date
                history.record(
                    joules: joules, seconds: Double(random.next(in: 1...600)), systemWatts: random.next(in: 0...4) == 0 ? nil : Double(random.next(in: 1...30)),
                    at: sampleDate)
            }
        }
        return (history, date)
    }

    private static func snapshot(_ percentage: Int, pluggedIn: Bool) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery, chargeState: pluggedIn ? .charging : .discharging,
            timeRemaining: nil)
    }

    @Test(arguments: seeds) func samplesStayInDateOrder(seed: UInt64) {
        let (history, _) = Self.randomHistory(seed: seed)
        #expect(zip(history.samples, history.samples.dropFirst()).allSatisfy { $0.date <= $1.date })
        #expect(zip(history.levels, history.levels.dropFirst()).allSatisfy { $0.date <= $1.date })
    }

    @Test(arguments: seeds) func trimMatchesTheReference(seed: UInt64) {
        let (history, end) = Self.randomHistory(seed: seed)
        for offset: TimeInterval in [0, 3600, 6 * 3600, 23.9 * 3600, 24 * 3600, 30 * 3600, 72 * 3600] {
            var trimmed = history
            trimmed.trim(now: end + offset)
            let reference = Reference.trim(history, now: end + offset)
            #expect(trimmed.levels == reference.levels)
            #expect(trimmed.samples == reference.samples)
            #expect(trimmed.apps == reference.apps)
        }
    }

    @Test(arguments: seeds) func readingsMatchTheReference(seed: UInt64) {
        let (history, end) = Self.randomHistory(seed: seed)
        let current = Self.snapshot(42, pluggedIn: false)
        for hoursBack: TimeInterval in [0, 0.5, 2, 12, 24, 36] {
            let start = end - hoursBack * 3600
            #expect(history.levels(since: start) == Reference.levels(history, since: start))
            #expect(history.sampledTime(since: start) == Reference.sampledTime(history, since: start))
            let energy = history.appEnergy(since: start)
            let reference = Reference.appEnergy(history, since: start)
            #expect(
                Dictionary(uniqueKeysWithValues: energy.map { ($0.id, $0.joules) }) == Dictionary(uniqueKeysWithValues: reference.map { ($0.id, $0.joules) }))
            let referenceTimes = Dictionary(uniqueKeysWithValues: reference.map { ($0.id, $0.batteryTime) })
            #expect(energy.allSatisfy { referenceTimes[$0.id] == .some($0.batteryTime) })
            #expect(energy.map(\.joules) == energy.map(\.joules).sorted(by: >))
        }
        #expect(history.levelBuckets(endingAt: end, current: current) == Reference.levelBuckets(history, endingAt: end, current: current))
        #expect(history.levelBuckets(endingAt: end + 5 * 3600, count: 17) == Reference.levelBuckets(history, endingAt: end + 5 * 3600, count: 17))
    }

    @Test(arguments: seeds) func smootherMatchesTheReference(seed: UInt64) {
        var random = SplitMix64(seed: seed)
        var smoother = PowerSmoother<Int32>()
        var reference: [Int32: Double] = [:]
        for _ in 0..<60 {
            var readings: [Int32: Double] = [:]
            for _ in 0..<random.next(in: 0...80) { readings[Int32(random.next(in: 0...120))] = Double(random.next(in: 0...3000)) / 1000 }
            smoother.add(readings)
            reference = Reference.smooth(reference, with: readings, responsiveness: smoother.responsiveness, floor: smoother.floor)
            #expect(smoother.values == reference)
        }
    }

    @Test func aSampleFromBeforeTheLastGoesInItsPlace() {
        var history = BatteryHistory()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let app = Self.apps[1]
        history.record(joules: [app: 1], seconds: 60, systemWatts: 5, at: start + 600)
        history.record(joules: [app: 2], seconds: 60, systemWatts: 5, at: start + 1200)
        history.record(joules: [app: 3], seconds: 60, systemWatts: 5, at: start + 900)
        #expect(history.samples.map { $0.joules[app.key] } == [1, 3, 2])
        // The out of order one counts for its last 50 seconds, the newest for all 60.
        #expect(history.sampledTime(since: start + 850) == 110)
    }

    @Test func emptyHistoryAnswersEverything() {
        let history = BatteryHistory()
        let now = Date()
        #expect(history.levels(since: now).isEmpty)
        #expect(history.appEnergy(since: now).isEmpty)
        #expect(history.sampledTime(since: now) == 0)
        #expect(history.levelBuckets(endingAt: now).allSatisfy { $0.percentage == nil })
        #expect(history.levelBuckets(endingAt: now, count: 0).isEmpty)
    }
}

/// The history's and smoother's algorithms as they were before they were made faster: simple, linear, obviously right.
private enum Reference {
    static func trim(_ history: BatteryHistory, now: Date) -> (
        levels: [BatteryHistory.LevelPoint], samples: [BatteryHistory.EnergySample], apps: [String: BatteryHistory.AppIdentity]
    ) {
        var levels = history.levels
        var samples = history.samples
        var apps = history.apps
        let cutoff = now.addingTimeInterval(-BatteryHistory.retention)
        if let firstKept = levels.firstIndex(where: { $0.date >= cutoff }), firstKept > 1 {
            levels.removeFirst(firstKept - 1)
        } else if levels.last.map({ $0.date < cutoff }) == true {
            levels.removeFirst(max(levels.count - 1, 0))
        }
        samples.removeAll { $0.date < cutoff }
        let used = Set(samples.flatMap(\.joules.keys))
        if apps.count > used.count { apps = apps.filter { used.contains($0.key) } }
        return (levels, samples, apps)
    }

    static func levels(_ history: BatteryHistory, since start: Date) -> [BatteryHistory.LevelPoint] {
        let levels = history.levels
        guard let firstInside = levels.firstIndex(where: { $0.date >= start }) else {
            return levels.last.map { [BatteryHistory.LevelPoint(date: start, percentage: $0.percentage, isPluggedIn: $0.isPluggedIn)] } ?? []
        }
        var points = Array(levels[firstInside...])
        if firstInside > 0 {
            let before = levels[firstInside - 1]
            points.insert(BatteryHistory.LevelPoint(date: start, percentage: before.percentage, isPluggedIn: before.isPluggedIn), at: 0)
        }
        return points
    }

    static func appEnergy(_ history: BatteryHistory, since start: Date) -> [BatteryHistory.AppEnergy] {
        let inRange = history.samples.filter { $0.date > start }
        var totals: [String: Double] = [:]
        for sample in inRange {
            let fraction = sample.start < start ? max(sample.date.timeIntervalSince(start), 0) / sample.seconds : 1
            for (key, joules) in sample.joules { totals[key, default: 0] += joules * fraction }
        }
        let readings = inRange.compactMap(\.systemWatts).filter { $0 > 0 }
        let averageWatts = readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)
        return totals.compactMap { key, joules in
            history.apps[key].map { BatteryHistory.AppEnergy(app: $0, joules: joules, batteryTime: averageWatts.map { joules / $0 }) }
        }
        .sorted { $0.joules > $1.joules }
    }

    static func sampledTime(_ history: BatteryHistory, since start: Date) -> TimeInterval {
        history.samples.filter { $0.date > start }.reduce(0) { $0 + min($1.seconds, $1.date.timeIntervalSince(start)) }
    }

    static func levelBuckets(_ history: BatteryHistory, endingAt now: Date, count: Int = 48, current: BatterySnapshot? = nil) -> [BatteryHistory.LevelBucket] {
        let levels = history.levels
        guard count > 0 else { return [] }
        let length = BatteryHistory.retention / Double(count)
        let start = now.addingTimeInterval(-BatteryHistory.retention)
        var buckets: [BatteryHistory.LevelBucket] = []
        var index = levels.firstIndex { $0.date >= start } ?? levels.endIndex
        var carried: BatteryHistory.LevelPoint? = index > levels.startIndex ? levels[index - 1] : nil
        for slot in 0..<count {
            let bucketStart = start.addingTimeInterval(Double(slot) * length)
            let bucketEnd = slot == count - 1 ? now : bucketStart.addingTimeInterval(length)
            var pluggedIn = carried?.isPluggedIn ?? false
            while index < levels.endIndex, levels[index].date < bucketEnd {
                carried = levels[index]
                pluggedIn = pluggedIn || levels[index].isPluggedIn
                index += 1
            }
            var percentage = carried?.percentage
            if slot == count - 1, let current, current.hasBattery, carried != nil {
                percentage = current.percentage
                pluggedIn = pluggedIn || current.isPluggedIn
            }
            buckets.append(BatteryHistory.LevelBucket(start: bucketStart, end: bucketEnd, percentage: percentage, isPluggedIn: percentage != nil && pluggedIn))
        }
        return buckets
    }

    static func smooth(_ values: [Int32: Double], with readings: [Int32: Double], responsiveness: Double, floor: Double) -> [Int32: Double] {
        var next: [Int32: Double] = [:]
        for key in Set(values.keys).union(readings.keys) {
            let reading = readings[key] ?? 0
            let value = values[key].map { $0 + responsiveness * (reading - $0) } ?? reading
            if value >= floor { next[key] = value }
        }
        return next
    }
}

/// A small, seeded random number generator, so a failing case can be replayed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }
}
