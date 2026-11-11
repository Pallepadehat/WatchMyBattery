import Foundation

// Times BatteryKit's hot paths and holds them against a budget and a baseline.
//
//   swift run -c release BatteryKitBenchmarks                    check against the budgets and Benchmarks/baseline.json
//   swift run -c release BatteryKitBenchmarks --update-baseline  record this Mac's numbers as the new baseline
//   swift run -c release BatteryKitBenchmarks --report-only      print, never fail (CI, where runners vary)
//   swift run -c release BatteryKitBenchmarks --quick            fewer, shorter batches
//   swift run -c release BatteryKitBenchmarks --filter history   only benchmarks whose name contains "history"
//   swift run -c release BatteryKitBenchmarks --json out.json    also write the results as JSON
//
// It exits with 1 when a benchmark goes over its budget, or over its baseline by more than its tolerance on the
// Mac that recorded the baseline. On another Mac only the budgets apply, as its numbers aren't comparable.

struct Options {
    var updateBaseline = false
    var reportOnly = false
    var quick = false
    var filter: String?
    var jsonPath: String?
    var baselinePath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Benchmarks/baseline.json").path

    init(_ arguments: [String]) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--update-baseline": updateBaseline = true
            case "--report-only": reportOnly = true
            case "--quick": quick = true
            case "--filter": filter = iterator.next()
            case "--json": jsonPath = iterator.next()
            case "--baseline": baselinePath = iterator.next() ?? baselinePath
            default:
                FileHandle.standardError.write(Data("Unknown option: \(argument)\n".utf8))
                exit(2)
            }
        }
    }
}

#if DEBUG
    print("⚠️  This is a debug build, so the numbers mean little. Run it with: swift run -c release BatteryKitBenchmarks\n")
#endif

let options = Options(Array(CommandLine.arguments.dropFirst()))
let machine = Machine.identifier
let baseline = (try? Data(contentsOf: URL(fileURLWithPath: options.baselinePath)))
    .flatMap { try? JSONDecoder().decode(Baseline.self, from: $0) }
let comparesBaseline = baseline?.machine == machine && !options.updateBaseline

print("Machine:  \(machine)")
if let baseline {
    print("Baseline: \(baseline.machine), recorded \(baseline.recorded)\(comparesBaseline ? "" : " (another Mac: only budgets apply)")")
} else {
    print("Baseline: none at \(options.baselinePath) (only budgets apply)")
}
print("")

let selected = Benchmarks.all.filter { options.filter.map($0.name.contains) ?? true }
let nameWidth = max(selected.map(\.name.count).max() ?? 0, 9)
func pad(_ text: String, _ width: Int) -> String { text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0) }
print(pad("Benchmark", nameWidth), pad("Median", 11), pad("Budget", 11), pad("Baseline", 11), "Result")

var results: [String: Measurement] = [:]
var failures: [String] = []
for benchmark in selected {
    let measurement = await Harness.measure(benchmark, quick: options.quick)
    results[benchmark.name] = measurement
    let budget = Double(benchmark.budget.nanoseconds)
    var verdict = "ok"
    var baselineText = "–"
    if measurement.medianNanoseconds > budget {
        verdict = "OVER BUDGET"
        failures.append("\(benchmark.name) took \(formatNanoseconds(measurement.medianNanoseconds)), over its budget of \(formatNanoseconds(budget))")
    }
    if let before = baseline?.results[benchmark.name] {
        let change = measurement.medianNanoseconds / before.medianNanoseconds - 1
        baselineText = formatNanoseconds(before.medianNanoseconds)
        let changeText = String(format: "%+.0f%%", change * 100)
        if comparesBaseline, change > benchmark.tolerance {
            verdict = verdict == "ok" ? "REGRESSED \(changeText)" : verdict + ", REGRESSED \(changeText)"
            failures.append(
                "\(benchmark.name) is \(changeText) slower than the baseline (allowed: +\(Int(benchmark.tolerance * 100))%)")
        } else if verdict == "ok" {
            verdict = "ok \(changeText)"
        }
    }
    print(
        pad(benchmark.name, nameWidth), pad(formatNanoseconds(measurement.medianNanoseconds), 11), pad(formatNanoseconds(budget), 11),
        pad(baselineText, 11), verdict)
}

if let jsonPath = options.jsonPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let report = Baseline(machine: machine, recorded: Date().formatted(.iso8601), results: results)
    try? encoder.encode(report).write(to: URL(fileURLWithPath: jsonPath))
}

if options.updateBaseline {
    // Keep the numbers of benchmarks that weren't run this time.
    var merged = baseline?.machine == machine ? baseline?.results ?? [:] : [:]
    merged.merge(results) { $1 }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let updated = Baseline(machine: machine, recorded: Date().formatted(.iso8601.year().month().day()), results: merged)
    do {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: options.baselinePath).deletingLastPathComponent(), withIntermediateDirectories: true)
        try (encoder.encode(updated) + Data("\n".utf8)).write(to: URL(fileURLWithPath: options.baselinePath))
        print("\nRecorded the baseline in \(options.baselinePath)")
    } catch {
        print("\nCouldn't write the baseline: \(error.localizedDescription)")
        exit(1)
    }
}

print("")
if failures.isEmpty {
    print("✅ All \(selected.count) benchmarks are within their budgets\(comparesBaseline ? " and the baseline" : "").")
} else {
    print("❌ \(failures.count) problem\(failures.count == 1 ? "" : "s"):")
    for failure in failures { print("   • \(failure)") }
    if !options.reportOnly { exit(1) }
}
