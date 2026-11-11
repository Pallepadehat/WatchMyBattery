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
    /// Processes we may not read (other users', the system's): about a third of them on a typical Mac. They're
    /// skipped until ``unreadableRecheck`` has passed, rather than asked again every two seconds.
    private var unreadable: [pid_t: ContinuousClock.Instant] = [:]
    /// Filled by `proc_listallpids`, kept from one sample to the next.
    private var pidBuffer: [pid_t] = []

    /// How long an unreadable process is skipped before it's tried again. Process IDs get reused, so an app
    /// that's given the ID of an unreadable process that just quit is measured this much later at most.
    static let unreadableRecheck: Duration = .seconds(30)

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
        // Rebuilt every time, so processes that are gone drop out of it.
        var stillUnreadable: [pid_t: ContinuousClock.Instant] = [:]
        stillUnreadable.reserveCapacity(unreadable.count + 16)

        let count = Self.listProcessIDs(into: &pidBuffer)
        for pid in pidBuffer.prefix(count) {
            if let since = unreadable[pid], now - since < Self.unreadableRecheck {
                stillUnreadable[pid] = since
                continue
            }
            guard let energy = Self.energy(of: pid) else {
                stillUnreadable[pid] = now
                continue
            }
            // A process's responsible app never changes, so look it up once.
            let responsible = previous[pid]?.responsiblePID ?? Responsibility.responsiblePID(for: pid)
            current[pid] = Reading(energy: energy, responsiblePID: responsible)
        }
        unreadable = stillUnreadable

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
        unreadable = [:]
    }

    // MARK: - System calls

    /// Fills `pids` with every process's ID, growing it when there are more than fit, and returns how many there are.
    private static func listProcessIDs(into pids: inout [pid_t]) -> Int {
        while true {
            if pids.isEmpty {
                let estimate = proc_listallpids(nil, 0)
                guard estimate > 0 else { return 0 }
                // Leave room for processes started in the meantime.
                pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
            }
            let count = pids.withUnsafeMutableBytes { buffer in
                proc_listallpids(buffer.baseAddress, Int32(buffer.count))
            }
            guard count > 0 else { return 0 }
            // A full buffer may have cut the list short: make room and ask again.
            guard Int(count) >= pids.count else { return Int(count) }
            pids = [pid_t](repeating: 0, count: pids.count * 2)
        }
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
