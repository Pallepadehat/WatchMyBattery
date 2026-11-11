import Foundation
import Testing

@testable import BatteryKit

struct RunawayDetectorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A five-minute sample ending `index` samples in, with each app's average watts.
    private func sample(_ index: Int, _ watts: [String: Double]) -> BatteryHistory.EnergySample {
        BatteryHistory.EnergySample(
            date: start.addingTimeInterval(Double(index) * 300), seconds: 300, joules: watts.mapValues { $0 * 300 }, systemWatts: nil)
    }

    @Test func reportsAnAppThatKeepsItUpForTheWindow() {
        var detector = RunawayDetector(threshold: 4, window: 15 * 60)
        #expect(detector.add(sample(1, ["busy": 6, "quiet": 1])) == [])
        #expect(detector.add(sample(2, ["busy": 6, "quiet": 1])) == [])
        #expect(detector.add(sample(3, ["busy": 6, "quiet": 1])) == ["busy"])
        #expect(detector.averageWatts(of: "busy") == 6)
        // Once only.
        #expect(detector.add(sample(4, ["busy": 6])) == [])
    }

    @Test func aShortBurstIsntARunaway() {
        var detector = RunawayDetector(threshold: 4, window: 15 * 60)
        _ = detector.add(sample(1, ["app": 1]))
        _ = detector.add(sample(2, ["app": 9]))
        #expect(detector.add(sample(3, ["app": 1])) == [])
    }

    @Test func reportsAgainAfterCalmingDown() {
        var detector = RunawayDetector(threshold: 4, window: 15 * 60)
        for index in 1...3 { _ = detector.add(sample(index, ["app": 5])) }
        #expect(detector.reported == ["app"])
        for index in 4...6 { _ = detector.add(sample(index, ["app": 0.5])) }
        #expect(detector.reported.isEmpty)
        _ = detector.add(sample(7, ["app": 5]))
        _ = detector.add(sample(8, ["app": 5]))
        #expect(detector.add(sample(9, ["app": 5])) == ["app"])
    }

    @Test func aGapStartsOver() {
        var detector = RunawayDetector(threshold: 4, window: 15 * 60)
        _ = detector.add(sample(1, ["app": 5]))
        _ = detector.add(sample(2, ["app": 5]))
        // An hour unplugged from sampling.
        #expect(detector.add(sample(14, ["app": 5])) == [])
        _ = detector.add(sample(15, ["app": 5]))
        #expect(detector.add(sample(16, ["app": 5])) == ["app"])
    }
}
