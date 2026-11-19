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
    ///
    /// Started with `posix_spawn` and read straight from a pipe: Foundation's `Process` costs several times what `ps`
    /// itself does, in setting up and watching for its end, which adds up every few seconds while the panel's open.
    static func read() -> [pid_t: Double]? {
        guard let output = run("/bin/ps", ["-A", "-o", "pid=,time="]) else { return nil }
        return parse(String(decoding: output, as: UTF8.self))
    }

    /// Runs a program and returns what it wrote, or `nil` if it couldn't be run or failed.
    static func run(_ path: String, _ arguments: [String]) -> [UInt8]? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        let (readEnd, writeEnd) = (fds[0], fds[1])
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, writeEnd, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addclose(&actions, readEnd)
        posix_spawn_file_actions_addclose(&actions, writeEnd)

        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
        defer { for argument in argv { free(argument) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, path, &actions, nil, argv, nil)
        close(writeEnd)
        guard spawned == 0 else {
            close(readEnd)
            return nil
        }

        var output: [UInt8] = []
        output.reserveCapacity(32_768)
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(readEnd, $0.baseAddress, $0.count) }
            if count > 0 {
                output.append(contentsOf: buffer[..<count])
            } else if count == 0 || errno != EINTR {
                break
            }
        }
        close(readEnd)

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        // Exited normally (no signal), with 0.
        return status & 0x7f == 0 && (status >> 8) & 0xff == 0 ? output : nil
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
