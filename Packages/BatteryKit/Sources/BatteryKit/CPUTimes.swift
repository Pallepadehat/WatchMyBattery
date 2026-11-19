import Darwin
import Foundation

/// How much CPU time every process has used, macOS's own and other users' included: the processes the kernel won't
/// show an app their energy for (about a third of them, WindowServer, Spotlight and the kernel among them).
///
/// `ps` is the one way in without administrator rights: macOS installs it set to run as root, so it can read every
/// process's CPU time. Running it takes about 10 ms, so it's run every few seconds, not every sample, and only CPU
/// time is asked for.
enum CPUTimes {
    /// Seconds of CPU time used by each process since it started; `nil` if `ps` couldn't be run.
    static func read() -> [pid_t: Double]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=,time="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// `ps`'s lines: a process ID and its time, as `[[dd-]hh:]mm:ss.cc`. Separate so it can be tested.
    static func parse(_ output: String) -> [pid_t: Double] {
        var times: [pid_t: Double] = [:]
        times.reserveCapacity(1024)
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = pid_t(fields[0]), let seconds = seconds(fields[1]) else { continue }
            times[pid] = seconds
        }
        return times
    }

    /// "12:49.93" → 769.93; "1:02:03.50" → 3723.5; "2-01:00:00.00" → 176400.
    static func seconds(_ field: Substring) -> Double? {
        var rest = field
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let value = Double(rest[..<dash]) else { return nil }
            days = value
            rest = rest[rest.index(after: dash)...]
        }
        var total = 0.0
        for part in rest.split(separator: ":") {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return days * 86_400 + total
    }
}

/// Watts from CPU time, for processes whose energy can't be read: what the processes that can be read used per second
/// of CPU time, applied to the others' CPU time. A rough figure, as cores differ (an efficiency core uses a fraction of
/// what a performance core does), so it's kept within sensible bounds and never allowed to claim more than the Mac draws.
struct CPUEnergyCalibration {
    /// Joules per second of CPU time, smoothed over samples.
    private(set) var joulesPerCPUSecond = defaultJoulesPerCPUSecond

    /// Before anything's measured: between an efficiency core's and a performance core's.
    static let defaultJoulesPerCPUSecond = 1.0
    /// Background work runs mostly on efficiency cores and busy apps on performance ones, so what apps show is
    /// clamped to this range rather than taken as is.
    static let range = 0.3...2.5

    /// Folds in one sample: the joules the readable processes used, and the CPU seconds they took.
    mutating func add(joules: Double, cpuSeconds: Double) {
        guard cpuSeconds > 0.02, joules > 0 else { return }
        let measured = min(max(joules / cpuSeconds, Self.range.lowerBound), Self.range.upperBound)
        joulesPerCPUSecond += 0.2 * (measured - joulesPerCPUSecond)
    }
}
