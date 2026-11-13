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
    /// Each process's watts in the last sample, with the app responsible for it: what a slice's breakdown shows.
    private var lastProcesses: [pid_t: (responsible: pid_t, watts: Double)] = [:]

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
        var processes: [pid_t: (responsible: pid_t, watts: Double)] = [:]
        for (pid, reading) in current {
            // A process we hadn't seen yet (or a reused PID) has no baseline to compare against.
            guard let before = previous[pid], reading.energy >= before.energy else { continue }
            let used = reading.energy - before.energy
            guard used > 0 else { continue }
            let processJoules = Double(used) / 1_000_000_000
            joules[reading.responsiblePID, default: 0] += processJoules
            processes[pid] = (reading.responsiblePID, processJoules / seconds)
        }
        lastProcesses = processes
        return (joules, seconds)
    }

    /// Forgets the baseline, so the next ``sample()`` starts afresh.
    public func reset() {
        previous = [:]
        previousTime = nil
        unreadable = [:]
        lastProcesses = [:]
    }

    /// The processes an app was responsible for in the last sample, hungriest first: the app itself, and the
    /// helpers, renderers and services it started. Nothing new is measured: it's the last sample, split up.
    public func processes(of responsiblePID: pid_t) -> [ProcessEnergy] {
        lastProcesses
            .filter { $0.value.responsible == responsiblePID }
            .map { pid, value in ProcessEnergy(pid: pid, name: ProcessName.of(pid), watts: value.watts, isApp: pid == responsiblePID) }
            .sorted { $0.watts != $1.watts ? $0.watts > $1.watts : $0.pid < $1.pid }
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

/// One process's share of an app's power.
public struct ProcessEnergy: Sendable, Equatable, Identifiable {
    public let pid: pid_t
    /// "Google Chrome Helper (Renderer)": the executable's name, which for helpers says what they do.
    public let name: String
    public let watts: Double
    /// The app's own process, rather than one it started.
    public let isApp: Bool

    public var id: pid_t { pid }

    public init(pid: pid_t, name: String, watts: Double, isApp: Bool) {
        self.pid = pid
        self.name = name
        self.watts = watts
        self.isApp = isApp
    }
}

/// A process's name from its executable's path, which isn't cut short at 16 or 32 characters like `proc_name`'s.
public enum ProcessName {
    public static func of(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if let name = path.split(separator: "/").last, !name.isEmpty { return String(name) }
        }
        var short = [CChar](repeating: 0, count: 64)
        proc_name(pid, &short, UInt32(short.count))
        let name = String(decoding: short.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? "\(pid)" : name
    }
}

extension Duration {
    fileprivate var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
