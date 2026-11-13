#!/usr/bin/env swift  // End-to-end checks of the real app: launches WatchMyBattery.app the way people run it, checks that it works, and
// measures what it costs, with the same counters Activity Monitor reads (CPU time, wake-ups, energy, memory).
//
//   swift scripts/e2e.swift --app build/E2E/Release/WatchMyBattery.app [--debug-app build/E2E/Debug/WatchMyBattery.app]
//
//   --quick             shorter measurements (CI)
//   --report-only       print, never fail on numbers (functional checks still fail)
//   --update-baseline   record this Mac's numbers in scripts/e2e-baseline.json
//   --json <path>       also write the results as JSON
//   --only idle,panel   only these scenarios (idle, charging, panel)
//
// Every run is isolated (`--isolated <folder>`): its own settings, a history store in a temporary folder, no
// updater, no keyboard shortcut, so it runs safely next to the copy you use. A second battery shows up in the menu
// bar while it runs. Don't click it: the panel scenario needs the panel to stay open.
//
// It exits with 1 when the app fails a check, or (unless --report-only) goes over a budget, or over the baseline by
// more than its tolerance on the Mac that recorded the baseline.

import AppKit
import Darwin
import Foundation
import SQLite3

// MARK: - Options

struct Options {
    var app: URL?
    var debugApp: URL?
    var quick = false
    var reportOnly = false
    var updateBaseline = false
    var jsonPath: String?
    /// Only these scenarios (`--only idle,panel`); all of them when empty.
    var only: Set<String> = []

    init(_ arguments: [String]) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--app": app = iterator.next().map { URL(fileURLWithPath: $0) }
            case "--debug-app": debugApp = iterator.next().map { URL(fileURLWithPath: $0) }
            case "--quick": quick = true
            case "--report-only": reportOnly = true
            case "--update-baseline": updateBaseline = true
            case "--json": jsonPath = iterator.next()
            case "--only": only = Set((iterator.next() ?? "").split(separator: ",").map(String.init))
            default: fail("Unknown option: \(argument)", code: 2)
            }
        }
    }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
    exit(code)
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
guard let appURL = options.app else { fail("Pass the app to check: --app path/to/WatchMyBattery.app", code: 2) }
let executable = appURL.appending(path: "Contents/MacOS/WatchMyBattery")
guard FileManager.default.isExecutableFile(atPath: executable.path) else { fail("No app at \(appURL.path)") }
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let baselineURL = repository.appending(path: "scripts/e2e-baseline.json")
let isolatedDomain = "com.pallepadehat.WatchMyBattery.isolated"

// MARK: - Measuring a process

/// What the kernel has counted for a process since it started.
struct Usage {
    var cpuNanoseconds: Double
    var wakeups: Double
    var energyNanojoules: Double
    var footprintBytes: Double

    static func of(_ pid: pid_t) -> Usage? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        guard result == 0 else { return nil }
        // CPU times are in Mach ticks, which aren't nanoseconds on Apple silicon.
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        return Usage(
            cpuNanoseconds: ticks * Double(timebase.numer) / Double(timebase.denom),
            wakeups: Double(info.ri_pkg_idle_wkups + info.ri_interrupt_wkups),
            energyNanojoules: Double(info.ri_energy_nj),
            footprintBytes: Double(info.ri_phys_footprint))
    }
}

/// A scenario's numbers, per minute so short and long runs compare.
struct Result: Codable {
    var cpuMillisecondsPerMinute: Double
    var wakeupsPerSecond: Double
    var energyMillijoulesPerMinute: Double
    var memoryMegabytes: Double
}

/// A running copy of the app, isolated from the real one.
final class RunningApp {
    let process = Process()
    let folder: URL
    private let output = Pipe()

    init(arguments: [String]) throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "WatchMyBattery-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        process.executableURL = executable
        process.arguments = ["--isolated", folder.path] + arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
    }

    var pid: pid_t { process.processIdentifier }
    /// The history's SwiftData store (SQLite underneath).
    var historyStore: URL { folder.appending(path: "History.store") }

    /// How many level readings the store holds, read straight from SQLite; `nil` if it can't be read.
    func storedLevels() -> Int? {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(historyStore.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM ZSTOREDLEVEL", -1, &statement, nil) == SQLITE_OK,
            sqlite3_step(statement) == SQLITE_ROW
        else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Waits until `condition` holds, checking every 0.1 s; `false` if it didn't in time.
    func wait(upTo seconds: Double, for condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            usleep(100_000)
        }
        return condition()
    }

    /// Measures for `seconds`, after letting it settle.
    func measure(settle: Double, seconds: Double) -> Result? {
        Thread.sleep(forTimeInterval: settle)
        guard process.isRunning, let before = Usage.of(pid) else { return nil }
        Thread.sleep(forTimeInterval: seconds)
        guard process.isRunning, let after = Usage.of(pid) else { return nil }
        let perMinute = 60 / seconds
        return Result(
            cpuMillisecondsPerMinute: (after.cpuNanoseconds - before.cpuNanoseconds) / 1e6 * perMinute,
            wakeupsPerSecond: (after.wakeups - before.wakeups) / seconds,
            energyMillijoulesPerMinute: (after.energyNanojoules - before.energyNanojoules) / 1e6 * perMinute,
            memoryMegabytes: after.footprintBytes / 1_048_576)
    }

    /// Quits it the way the menu's Quit does, so it saves what it has. `false` if it didn't go.
    func quit() -> Bool {
        guard process.isRunning else { return false }
        NSRunningApplication(processIdentifier: pid)?.terminate()
        if wait(upTo: 10, for: { !process.isRunning }) { return true }
        process.terminate()
        return false
    }

    func cleanUp() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: folder)
    }

    /// The first lines it printed, for saying why it failed.
    var log: String {
        String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).split(separator: "\n").prefix(4).joined(separator: "\n")
    }
}

// MARK: - Budgets

/// What the app may cost in a scenario, on any Mac. Mostly from CONTRIBUTING: it has to stay idle while its panel
/// is closed, the charging animation has to be cheap, and the open panel samples every two seconds and no more.
struct Budget {
    var cpuMillisecondsPerMinute: Double
    var wakeupsPerSecond: Double
    var memoryMegabytes: Double
}

let budgets: [String: Budget] = [
    // Closed panel, nothing happening: a quarter of a percent of one core at most. What it measures (10–90 ms) is
    // almost all AppKit handling the window server's messages, which every menu bar app gets, more on a busy Mac.
    // Anything that starts polling goes far past this.
    "idle": Budget(cpuMillisecondsPerMinute: 150, wakeupsPerSecond: 2, memoryMegabytes: 120),
    // The menu bar glint while charging: a second of frames every three seconds. Each frame costs macOS a few
    // milliseconds in the app (it re-snapshots the icon for the menu bar), about 4 s a minute in all on an M3 Pro.
    "charging": Budget(cpuMillisecondsPerMinute: 6000, wakeupsPerSecond: 40, memoryMegabytes: 120),
    // The panel open, measuring apps every two seconds (about 350 ms a minute).
    "panel": Budget(cpuMillisecondsPerMinute: 1500, wakeupsPerSecond: 15, memoryMegabytes: 160),
]

/// How much worse than the baseline a number may get before it counts as a regression, and an absolute allowance
/// below which a change is noise (a few milliseconds of CPU a minute is nothing, whatever the percentage).
let tolerance = 0.5
let slack = (cpu: 30.0, wakeups: 1.0, memory: 15.0)

// MARK: - Running the scenarios

struct Baseline: Codable {
    var machine: String
    var recorded: String
    var results: [String: Result]
}

func machineIdentifier() -> String {
    func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    return "\(sysctl("hw.model")), \(sysctl("machdep.cpu.brand_string"))"
}

var checks: [(name: String, passed: Bool, detail: String)] = []
func check(_ name: String, _ passed: Bool, _ detail: String = "") {
    checks.append((name, passed, detail))
    print("  \(passed ? "✔" : "✘") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
}

let machine = machineIdentifier()
let baseline = (try? Data(contentsOf: baselineURL)).flatMap { try? JSONDecoder().decode(Baseline.self, from: $0) }
let comparesBaseline = baseline?.machine == machine && !options.updateBaseline
let measureSeconds: Double = options.quick ? 10 : 20
/// Each scenario runs this many times, and the least of them counts.
let runs = options.quick ? 2 : 3
var results: [String: Result] = [:]

print("App:      \(appURL.path)")
print("Machine:  \(machine)")
if let baseline {
    print("Baseline: \(baseline.machine), recorded \(baseline.recorded)\(comparesBaseline ? "" : " (another Mac: only budgets apply)")")
} else {
    print("Baseline: none (only budgets apply)")
}

let macHasBattery: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g", "batt"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).contains("InternalBattery")
}()

/// Launches the app with `arguments`, checks it comes up, and measures it.
func scenario(_ name: String, _ title: String, arguments: [String], keepsHistory: Bool = true) {
    guard options.only.isEmpty || options.only.contains(name) else { return }
    print("\n\(title)")
    var measured: [Result] = []
    for run in 1...runs {
        guard let result = launchAndMeasure(arguments: arguments, keepsHistory: keepsHistory, reportsChecks: run == 1) else { return }
        measured.append(result)
        print(
            String(
                format: "  run %d: CPU %.1f ms/min (%.3f%% of a core) · %.2f wake-ups/s · %.0f mJ/min · %.1f MB", run,
                result.cpuMillisecondsPerMinute, result.cpuMillisecondsPerMinute / 600, result.wakeupsPerSecond,
                result.energyMillijoulesPerMinute, result.memoryMegabytes))
    }
    // Whatever else the Mac is doing only ever adds to the numbers, so the least of the runs is the app's own cost.
    results[name] = Result(
        cpuMillisecondsPerMinute: measured.map(\.cpuMillisecondsPerMinute).min() ?? 0,
        wakeupsPerSecond: measured.map(\.wakeupsPerSecond).min() ?? 0,
        energyMillijoulesPerMinute: measured.map(\.energyMillijoulesPerMinute).min() ?? 0,
        memoryMegabytes: measured.map(\.memoryMegabytes).min() ?? 0)
}

/// One run: launches the app, checks that it works (reporting the checks on the first run, and any that fail on
/// later ones), measures it, and quits it.
func launchAndMeasure(arguments: [String], keepsHistory: Bool, reportsChecks: Bool) -> Result? {
    func verify(_ name: String, _ passed: Bool, _ detail: String = "") {
        if reportsChecks || !passed { check(name, passed, detail) }
    }
    let app: RunningApp
    do {
        app = try RunningApp(arguments: arguments)
    } catch {
        verify("launches", false, error.localizedDescription)
        return nil
    }
    defer { app.cleanUp() }

    // The history's store is opened at launch, and the first battery reading saved into it straight away (on Macs
    // with a battery). A made-up battery (`--pretend-charging`) is kept in memory only, on purpose.
    let hasBattery = macHasBattery && keepsHistory
    let started = Date()
    let launched = app.wait(upTo: 15) { !app.process.isRunning || !hasBattery || (app.storedLevels() ?? 0) > 0 }
    verify(
        "launches and keeps running", launched && app.process.isRunning, app.process.isRunning ? "" : "exited with \(app.process.terminationStatus)\n\(app.log)"
    )
    guard app.process.isRunning else { return nil }
    if hasBattery {
        verify(
            "records the battery to its history store", (app.storedLevels() ?? 0) > 0,
            String(format: "after %.1f s", Date().timeIntervalSince(started)))
    }

    guard let result = app.measure(settle: 3, seconds: measureSeconds) else {
        verify("stays up while measured", false, app.log)
        return nil
    }

    let quit = app.quit()
    verify("quits when asked", quit, quit ? "" : "it had to be killed")
    if quit {
        verify("exits cleanly", app.process.terminationStatus == 0, "status \(app.process.terminationStatus)")
    }
    if quit, hasBattery {
        verify("leaves a readable history behind", (app.storedLevels() ?? 0) > 0)
    }
    return result
}

// Idle and panel with the animation off, so they're the same whether this Mac happens to be charging or not: the
// animation has its own scenario, and playing it in the panel would measure the animation rather than the panel.
scenario("idle", "Idle: panel closed, nothing to animate", arguments: ["-showsChargingAnimation", "NO"])
scenario("charging", "Charging: the menu bar animation playing", arguments: ["--pretend-charging"], keepsHistory: false)
scenario("panel", "Panel open: measuring apps every two seconds", arguments: ["--show-panel", "-showsChargingAnimation", "NO"])

// Clean up after the isolated runs' settings. (Their menu bar icon keeps its own position under its own name, so
// the real app's isn't touched.)
for arguments in [["delete", isolatedDomain]] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

// MARK: - Previews (debug builds only)

if let debugApp = options.debugApp {
    print("\nPreviews: the debug build renders the panel and icons to images")
    let folder = FileManager.default.temporaryDirectory.appending(path: "WatchMyBattery-previews-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let process = Process()
    process.executableURL = debugApp.appending(path: "Contents/MacOS/WatchMyBattery")
    process.arguments = ["--render-previews", folder.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let started = Date()
    if (try? process.run()) == nil {
        check("renders previews", false, "couldn't start \(debugApp.path)")
    } else {
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning, Date() < deadline { usleep(100_000) }
        if process.isRunning { process.terminate() }
        check(
            "renders previews and exits", !process.isRunning && process.terminationStatus == 0,
            String(format: "%.1f s", Date().timeIntervalSince(started)))
        var expected = ["icons.png", "glint.png", "card-dark.png", "card-light.png", "airpods-card-dark.png", "airpods-card-light.png"]
        for state in ["discharging", "low", "charging", "half", "full"] {
            for scheme in ["dark", "light"] { expected.append("panel-\(state)-\(scheme).png") }
        }
        let missing = expected.filter { name in
            // A real image, not an empty file: a few kilobytes at least, and big enough to show something.
            guard let image = NSImage(contentsOf: folder.appending(path: name)), let rep = image.representations.first else { return true }
            return rep.pixelsWide < 200 || rep.pixelsHigh < 50
        }
        check("draws every preview", missing.isEmpty, missing.isEmpty ? "\(expected.count) images" : "missing or empty: \(missing.joined(separator: ", "))")
    }
}

// MARK: - Verdict

print("\nCosts")
var problems: [String] = []
let names = ["idle", "charging", "panel"]
print("  Scenario   CPU ms/min   Wake-ups/s   Memory MB   vs. baseline")
for name in names {
    guard let result = results[name], let budget = budgets[name] else { continue }
    var notes: [String] = []
    if result.cpuMillisecondsPerMinute > budget.cpuMillisecondsPerMinute {
        problems.append(
            String(format: "%@ uses %.0f ms of CPU a minute, over its budget of %.0f", name, result.cpuMillisecondsPerMinute, budget.cpuMillisecondsPerMinute))
    }
    if result.wakeupsPerSecond > budget.wakeupsPerSecond {
        problems.append(String(format: "%@ wakes up %.1f times a second, over its budget of %.1f", name, result.wakeupsPerSecond, budget.wakeupsPerSecond))
    }
    if result.memoryMegabytes > budget.memoryMegabytes {
        problems.append(String(format: "%@ uses %.0f MB, over its budget of %.0f", name, result.memoryMegabytes, budget.memoryMegabytes))
    }
    if let before = baseline?.results[name] {
        func compare(_ label: String, _ now: Double, _ then: Double, _ allowance: Double) {
            let change = then > 0 ? now / then - 1 : 0
            notes.append(String(format: "%@ %+.0f%%", label, change * 100))
            if comparesBaseline, now > then * (1 + tolerance), now - then > allowance {
                problems.append(String(format: "%@: %@ went from %.1f to %.1f", name, label, then, now))
            }
        }
        compare("CPU", result.cpuMillisecondsPerMinute, before.cpuMillisecondsPerMinute, slack.cpu)
        compare("wake-ups", result.wakeupsPerSecond, before.wakeupsPerSecond, slack.wakeups)
        compare("memory", result.memoryMegabytes, before.memoryMegabytes, slack.memory)
    }
    let row = String(format: "  %-9@  %10.1f   %10.2f   %9.1f", name, result.cpuMillisecondsPerMinute, result.wakeupsPerSecond, result.memoryMegabytes)
    print(row + "   " + (notes.isEmpty ? "–" : notes.joined(separator: ", ")))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let jsonPath = options.jsonPath {
    try? encoder.encode(Baseline(machine: machine, recorded: Date().formatted(.iso8601), results: results))
        .write(to: URL(fileURLWithPath: jsonPath))
}
if options.updateBaseline {
    let updated = Baseline(machine: machine, recorded: Date().formatted(.iso8601.year().month().day()), results: results)
    if let data = try? encoder.encode(updated), (try? (data + Data("\n".utf8)).write(to: baselineURL)) != nil {
        print("\nRecorded the baseline in \(baselineURL.path)")
    } else {
        fail("Couldn't write the baseline to \(baselineURL.path)")
    }
}

let failedChecks = checks.filter { !$0.passed }
print("")
if failedChecks.isEmpty && problems.isEmpty {
    print("✅ The app passed all \(checks.count) checks and stayed within its budgets\(comparesBaseline ? " and the baseline" : "").")
    exit(0)
}
for failed in failedChecks { print("❌ \(failed.name)\(failed.detail.isEmpty ? "" : ": \(failed.detail)")") }
for problem in problems { print("❌ \(problem)") }
exit(!failedChecks.isEmpty || !options.reportOnly ? 1 : 0)
