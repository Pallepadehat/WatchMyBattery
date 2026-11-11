import Darwin
import Foundation

/// One thing to time.
///
/// `budget` is an absolute ceiling per run that holds on any Mac: what the
/// app can afford, given how often it does this. `tolerance` is how much
/// slower than the recorded baseline it may get on the Mac that recorded it,
/// before it counts as a regression.
struct Benchmark: Sendable {
    let name: String
    let budget: Duration
    let tolerance: Double
    /// Makes the work to time; the closure it returns is called once per run.
    let make: @Sendable () async -> @Sendable () async -> Void

    init(
        _ name: String, budget: Duration, tolerance: Double = 0.5,
        make: @escaping @Sendable () async -> @Sendable () async -> Void
    ) {
        self.name = name
        self.budget = budget
        self.tolerance = tolerance
        self.make = make
    }
}

/// The timing of one benchmark: the median and fastest of several batches, per run.
struct Measurement: Codable {
    var medianNanoseconds: Double
    var minimumNanoseconds: Double
    var iterations: Int
}

/// Keeps the optimizer from throwing away work whose result isn't used.
@inline(never)
func blackHole<T>(_ value: T) {
    withExtendedLifetime(value) {}
}

enum Harness {
    /// Times `benchmark`: repeated in batches long enough to swamp the clock's overhead, and the median batch taken.
    static func measure(_ benchmark: Benchmark, quick: Bool) async -> Measurement {
        let run = await benchmark.make()
        let clock = ContinuousClock()
        let batchTarget: Duration = quick ? .milliseconds(5) : .milliseconds(25)
        let batchCount = quick ? 5 : 15

        // Warm up, and find how many runs fill a batch.
        await run()
        var iterations = 1
        while true {
            let elapsed = await clock.measure { for _ in 0..<iterations { await run() } }
            if elapsed >= batchTarget || iterations >= 1 << 20 { break }
            let scale = elapsed > .zero ? Double(batchTarget.nanoseconds) / Double(elapsed.nanoseconds) : 10
            iterations = max(iterations + 1, Int(Double(iterations) * min(scale * 1.2, 10)))
        }

        var perRun: [Double] = []
        for _ in 0..<batchCount {
            let elapsed = await clock.measure { for _ in 0..<iterations { await run() } }
            perRun.append(Double(elapsed.nanoseconds) / Double(iterations))
        }
        perRun.sort()
        return Measurement(medianNanoseconds: perRun[perRun.count / 2], minimumNanoseconds: perRun[0], iterations: iterations)
    }
}

/// What's recorded in `Benchmarks/baseline.json`.
struct Baseline: Codable {
    var machine: String
    var recorded: String
    var results: [String: Measurement]
}

extension Duration {
    var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}

/// The Mac this runs on, so a baseline is only held against the Mac that recorded it.
enum Machine {
    static var identifier: String {
        "\(sysctl("hw.model") ?? "unknown Mac"), \(sysctl("machdep.cpu.brand_string") ?? "unknown CPU")"
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// "1.23 µs"
func formatNanoseconds(_ value: Double) -> String {
    switch value {
    case ..<1_000: String(format: "%.0f ns", value)
    case ..<1_000_000: String(format: "%.2f µs", value / 1_000)
    case ..<1_000_000_000: String(format: "%.2f ms", value / 1_000_000)
    default: String(format: "%.2f s", value / 1_000_000_000)
    }
}
