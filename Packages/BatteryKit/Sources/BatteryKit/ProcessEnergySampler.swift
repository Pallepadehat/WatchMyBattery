import Darwin
import Foundation

/// Measures how much power each app is using, in watts.
///
/// The kernel keeps a running total of the energy every process has used
/// (`ri_energy_nj` in `proc_pid_rusage`). Each call to ``sample()`` reads
/// those totals and divides what was used since the previous call by the time
/// that passed. Helper processes (renderers, XPC services, and so on) are
/// counted toward the app that's responsible for them, which is how Activity
/// Monitor groups them too.
///
/// It's an actor so the few hundred system calls a sample takes happen off
/// the main thread.
public actor ProcessEnergySampler {
    private struct Reading {
        var energy: UInt64
        var responsiblePID: pid_t
    }

    private var previous: [pid_t: Reading] = [:]
    private var previousTime: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    public init() {}

    /// Watts used by each responsible app since the last call, keyed by the
    /// app's process ID. The first call only takes a baseline and returns an
    /// empty dictionary.
    public func sample() -> [pid_t: Double] {
        let (joules, seconds) = sampleEnergy()
        guard seconds > 0.05 else { return [:] }
        return joules.mapValues { $0 / seconds }
    }

    /// Joules used by each responsible app since the last call, and the seconds
    /// that took. For sampling rarely: the kernel's totals keep counting in
    /// between, so nothing is missed except processes that came and went.
    /// The first call only takes a baseline and returns nothing.
    public func sampleEnergy() -> (joules: [pid_t: Double], seconds: Double) {
        let now = clock.now
        var current: [pid_t: Reading] = [:]
        current.reserveCapacity(previous.count + 32)

        for pid in Self.allProcessIDs() {
            guard let energy = Self.energy(of: pid) else { continue }
            // A process's responsible app never changes, so look it up once.
            let responsible = previous[pid]?.responsiblePID ?? Responsibility.responsiblePID(for: pid)
            current[pid] = Reading(energy: energy, responsiblePID: responsible)
        }

        defer {
            previous = current
            previousTime = now
        }
        guard let previousTime else { return ([:], 0) }
        let seconds = (now - previousTime).seconds
        guard seconds > 0 else { return ([:], 0) }

        var joules: [pid_t: Double] = [:]
        for (pid, reading) in current {
            // A process we hadn't seen yet (or a reused PID) has no baseline to compare against.
            guard let before = previous[pid], reading.energy >= before.energy else { continue }
            let used = reading.energy - before.energy
            guard used > 0 else { continue }
            joules[reading.responsiblePID, default: 0] += Double(used) / 1_000_000_000
        }
        return (joules, seconds)
    }

    /// Forgets the baseline, so the next ``sample()`` starts afresh.
    public func reset() {
        previous = [:]
        previousTime = nil
    }

    // MARK: - System calls

    private static func allProcessIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Leave room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    /// The process's lifetime energy use in nanojoules, or `nil` when we may
    /// not read it (processes of other users, for example).
    private static func energy(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_energy_nj
    }
}

extension Duration {
    fileprivate var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
