import BatteryKit
import Foundation

/// Everything timed, with what the app can afford for each. Budgets follow
/// from how often the app does the work: something done every two seconds
/// while the panel is open has to be far cheaper than something done once
/// at launch. They're set well above what a Mac takes today, so only a real
/// regression (or a much slower Mac) trips them; the baseline catches
/// smaller slips on the Mac that recorded it.
enum Benchmarks {
    static let all: [Benchmark] = history + measuring + panel

    // MARK: - History: recorded all day, read when the panel opens

    static let history: [Benchmark] = [
        // On every battery level change, with a full day already held. The clock barely moves from run to run, so
        // the day stays full instead of the runs pushing it out of the 24 hours kept.
        Benchmark("history.recordLevel", budget: .microseconds(100)) {
            let state = Box((history: Fixtures.fullDay(), date: Fixtures.now, percentage: 50))
            return {
                state.value.date += 0.001
                state.value.percentage = state.value.percentage == 50 ? 49 : 50
                state.value.history.record(Fixtures.snapshot(state.value.percentage, pluggedIn: false), at: state.value.date)
            }
        },
        // Every five minutes on battery.
        Benchmark("history.recordSample", budget: .milliseconds(1)) {
            let state = Box((history: Fixtures.fullDay(), date: Fixtures.now, index: 0))
            return {
                state.value.date += 300
                state.value.index += 1
                state.value.history.record(
                    joules: Fixtures.joules(for: state.value.index), seconds: 300, systemWatts: 9, at: state.value.date)
            }
        },
        // Each time the panel draws its chart.
        Benchmark("history.levelBuckets", budget: .microseconds(200)) {
            let history = Fixtures.fullDay()
            let current = Fixtures.snapshot(40, pluggedIn: false)
            return { blackHole(history.levelBuckets(endingAt: Fixtures.now, current: current)) }
        },
        Benchmark("history.appEnergy", budget: .microseconds(500)) {
            let history = Fixtures.fullDay()
            let start = Fixtures.now.addingTimeInterval(-BatteryHistory.retention)
            return { blackHole(history.appEnergy(since: start)) }
        },
        Benchmark("history.sampledTime", budget: .microseconds(100)) {
            let history = Fixtures.fullDay()
            let start = Fixtures.now.addingTimeInterval(-BatteryHistory.retention)
            return { blackHole(history.sampledTime(since: start)) }
        },
        Benchmark("history.sinceUnplugged", budget: .microseconds(50)) {
            let history = Fixtures.fullDay()
            let current = Fixtures.snapshot(40, pluggedIn: false)
            return { blackHole(history.sinceUnplugged(current, now: Fixtures.now)) }
        },
        // Saved every five minutes on battery, off the main thread.
        Benchmark("history.save", budget: .milliseconds(30), tolerance: 1) {
            let history = Fixtures.fullDay()
            let url = FileManager.default.temporaryDirectory.appending(path: "BatteryKitBenchmarks-\(UUID().uuidString)/History.plist")
            return { try? history.save(to: url) }
        },
        // Once, at launch, on the main thread.
        Benchmark("history.load", budget: .milliseconds(50), tolerance: 1) {
            let url = FileManager.default.temporaryDirectory.appending(path: "BatteryKitBenchmarks-\(UUID().uuidString)/History.plist")
            // Recent enough that loading doesn't trim it all away.
            try? Fixtures.fullDay(endingAt: Date()).save(to: url)
            return { blackHole(BatteryHistory.load(from: url)) }
        },
    ]

    // MARK: - Measuring apps: every two seconds while the panel is open

    static let measuring: [Benchmark] = [
        // The real thing: every process on this Mac. Depends on how many are running, hence the wide tolerance.
        Benchmark("sampler.sampleEnergy", budget: .milliseconds(25), tolerance: 1.5) {
            let sampler = ProcessEnergySampler()
            _ = await sampler.sampleEnergy()
            return { blackHole(await sampler.sampleEnergy()) }
        },
        Benchmark("powerSource.read", budget: .milliseconds(2), tolerance: 1.5) {
            { blackHole(PowerSourceReader.read()) }
        },
        Benchmark("systemPower.currentWatts", budget: .milliseconds(5), tolerance: 1.5) {
            let reader = SystemPowerReader()
            return { blackHole(reader.currentWatts()) }
        },
        Benchmark("smoother.add", budget: .milliseconds(1)) {
            let state = Box((smoother: PowerSmoother<Int32>(), round: 0))
            let rounds = (0..<8).map { Fixtures.powerReadings(count: 400, round: $0) }
            return {
                state.value.round = (state.value.round + 1) % rounds.count
                state.value.smoother.add(rounds[state.value.round])
            }
        },
        // Every five minutes on battery.
        Benchmark("runaway.add", budget: .microseconds(100)) {
            let history = Fixtures.fullDay()
            let state = Box((detector: RunawayDetector(), index: 0))
            return {
                let samples = history.samples
                state.value.index = (state.value.index + 1) % samples.count
                var sample = samples[state.value.index]
                // Back to back, so the detector always has a continuous window to work with.
                sample.date = Fixtures.now.addingTimeInterval(Double(state.value.index) * 300)
                if state.value.index == 0 { state.value.detector.reset() }
                blackHole(state.value.detector.add(sample))
            }
        },
    ]

    // MARK: - The panel: on every redraw

    static let panel: [Benchmark] = [
        Benchmark("gauge.layout", budget: .microseconds(20)) {
            {
                blackHole(GaugeLayout(width: 288, level: 0.64, shares: [0.31, 0.18, 0.09, 0.04], labelWidth: 60))
            }
        },
        Benchmark("estimates.sliceShares", budget: .microseconds(20)) {
            let estimates = Estimates(snapshot: Fixtures.snapshot(64, pluggedIn: false), systemWatts: 14)
            return { blackHole(estimates.sliceShares(forAppsDrawing: [2.6, 1.4, 0.9, 0.3])) }
        },
        // Once per app that shows up, for its slice's colour.
        Benchmark("iconPalette.dominantColor", budget: .microseconds(500)) {
            let pixels = Fixtures.iconPixels()
            return { blackHole(IconPalette.dominantColor(rgba: pixels)) }
        },
        // Once per charging sweep, when the level changes.
        Benchmark("glint.frames", budget: .microseconds(50)) {
            { blackHole(ChargingGlint(bodyWidth: 23, level: 0.62)) }
        },
    ]
}
