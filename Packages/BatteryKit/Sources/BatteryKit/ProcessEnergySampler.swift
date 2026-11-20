import Darwin
import Foundation

/// Measures how much power each app is using, in watts.
///
/// The kernel keeps a running total of the energy every process has used
/// (`ri_energy_nj` in `proc_pid_rusage`). Each call to ``sample()`` reads
/// those totals and divides what was used since the previous call by the time
/// that passed. Those totals cover the CPU only, so the GPU's energy is added
/// on top, shared out by how long the GPU worked for each process (see
/// ``GPUEnergySampler``). Helper processes (renderers, XPC services, and so on)
/// are counted toward the app that's responsible for them, which is how
/// Activity Monitor groups them too, except that a command run in a terminal,
/// or a program running on its own, counts as itself (see ``Ownership``).
///
/// The kernel won't show an app the energy of other users' processes (macOS's
/// own: WindowServer, Spotlight, the kernel). For those, CPU time is read with
/// `ps` every few seconds, and turned into watts at the rate the readable
/// processes use energy per second of CPU (see ``CPUTimes``): an estimate,
/// marked as one, and never more than the Mac actually draws.
///
/// It's an actor so the few hundred system calls a sample takes happen off
/// the main thread.
public actor ProcessEnergySampler {
    private struct Reading {
        var energy: UInt64
        /// CPU time, in Mach time units (ticks of 41.67 ns on Apple silicon, nanoseconds on Intel).
        var cpuTime: UInt64
        /// When the process started, which tells it apart from a later one given the same ID.
        var started: UInt64
        /// Who its energy counts toward (see ``Ownership``): its app, or the command it's part of.
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
    private var lastProcesses: [pid_t: (responsible: pid_t, watts: Double, isEstimated: Bool)] = [:]

    // Processes that can't be read, measured by CPU time instead.
    private var calibration = CPUEnergyCalibration()
    /// `ps`'s last reading, and when it was taken.
    private var cpuTimes: [pid_t: Double] = [:]
    private var cpuTimesTakenAt: ContinuousClock.Instant?
    /// Each unreadable process's CPU use, in CPU seconds per second, from the last two `ps` readings.
    private var cpuRates: [pid_t: Double] = [:]
    /// Unreadable processes' owners, looked up once each.
    private var unreadableOwners: [pid_t: pid_t] = [:]
    private let systemPower = SystemPowerReader()
    /// Whether to estimate unreadable processes at all. The history, which samples every five minutes, does; so does
    /// the panel.
    private let estimatesUnreadable: Bool
    /// `ps` is run at most this often.
    static let cpuTimesInterval: Duration = .seconds(4)
    /// The second reading comes sooner. `ps` counts in hundredths of a second, plenty over this long for anything
    /// worth a slice.
    static let firstCPUTimesInterval: Duration = .milliseconds(400)
    /// What estimated processes may claim at most: this share of what's left of the Mac's draw once the measured
    /// processes have theirs. The display, Wi‑Fi and the rest always use something.
    static let estimatedShareOfRemainder = 0.8
    private static let ticksToSeconds: Double = {
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1e9
    }()
    /// The GPU's share of each process. Its readings are taken with the CPU's, so both cover the same span.
    private let gpu = GPUEnergySampler()

    /// How long an unreadable process is skipped before it's tried again. Process IDs get reused, so an app
    /// that's given the ID of an unreadable process that just quit is measured this much later at most.
    static let unreadableRecheck: Duration = .seconds(30)

    public init(estimatesUnreadable: Bool = true) {
        self.estimatesUnreadable = estimatesUnreadable
    }

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
            guard let usage = Self.usage(of: pid) else {
                stillUnreadable[pid] = now
                continue
            }
            // A process's owner doesn't change, so look it up once per process. IDs get reused, though, so
            // what was found last time only holds for the same process: the same ID and the same start.
            let before = previous[pid].flatMap { $0.started == usage.started ? $0 : nil }
            let responsible = before?.responsiblePID ?? Ownership.owner(of: pid)
            current[pid] = Reading(energy: usage.energy, cpuTime: usage.cpuTime, started: usage.started, responsiblePID: responsible)
        }
        unreadable = stillUnreadable
        let gpuJoules = gpu.sample()

        defer {
            previous = current
            previousTime = now
        }
        guard let previousTime else {
            // The first `ps` reading too, so the estimates are ready by the next sample.
            if estimatesUnreadable { refreshCPURates(now: now) }
            return ([:], 0)
        }
        let seconds = (now - previousTime).seconds
        guard seconds > 0 else { return ([:], 0) }

        var joules: [pid_t: Double] = [:]
        var processes: [pid_t: (responsible: pid_t, watts: Double, isEstimated: Bool)] = [:]
        var measuredJoules = 0.0
        var measuredCPUSeconds = 0.0
        for (pid, reading) in current {
            // A process we hadn't seen yet (or a reused PID) has no baseline to compare against.
            guard let before = previous[pid], before.started == reading.started, reading.energy >= before.energy else { continue }
            if reading.cpuTime > before.cpuTime { measuredCPUSeconds += Double(reading.cpuTime - before.cpuTime) * Self.ticksToSeconds }
            let used = reading.energy - before.energy
            guard used > 0 else { continue }
            let processJoules = Double(used) / 1_000_000_000
            measuredJoules += processJoules
            joules[reading.responsiblePID, default: 0] += processJoules
            processes[pid] = (reading.responsiblePID, processJoules / seconds, false)
        }
        calibration.add(joules: measuredJoules, cpuSeconds: measuredCPUSeconds)
        if estimatesUnreadable {
            estimateUnreadable(
                stillUnreadable.keys, seconds: seconds, measuredJoules: measuredJoules, now: now, into: &joules, processes: &processes)
        }
        // The GPU's part, which the kernel's totals leave out. Other users' processes (WindowServer, mostly) get theirs
        // too, though no app does, so it stays with display and system.
        for (pid, used) in gpuJoules {
            let responsible = current[pid]?.responsiblePID ?? Ownership.owner(of: pid)
            joules[responsible, default: 0] += used
            processes[pid] = (responsible, (processes[pid]?.watts ?? 0) + used / seconds, processes[pid]?.isEstimated ?? false)
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
        gpu.reset()
        cpuTimes = [:]
        cpuTimesTakenAt = nil
        cpuRates = [:]
        unreadableOwners = [:]
    }

    /// Adds the processes that can't be read, from their CPU time (see the type's description).
    private func estimateUnreadable(
        _ pids: Dictionary<pid_t, ContinuousClock.Instant>.Keys, seconds: Double, measuredJoules: Double, now: ContinuousClock.Instant,
        into joules: inout [pid_t: Double], processes: inout [pid_t: (responsible: pid_t, watts: Double, isEstimated: Bool)]
    ) {
        refreshCPURates(now: now)
        guard !cpuRates.isEmpty else { return }
        var estimated: [pid_t: Double] = [:]
        var total = 0.0
        for pid in pids {
            guard let rate = cpuRates[pid], rate > 0 else { continue }
            let used = rate * seconds * calibration.joulesPerCPUSecond
            estimated[pid] = used
            total += used
        }
        guard total > 0 else { return }
        // Never more than the Mac draws: what's left once the measured processes have theirs, less the display's and
        // the hardware's part. Only for a sample short enough that the draw right now stands for it.
        var scale = 1.0
        if seconds <= 30, let system = systemPower.currentWatts() {
            let remainder = max(system * seconds - measuredJoules, 0) * Self.estimatedShareOfRemainder
            if total > remainder { scale = remainder / total }
        }
        for (pid, used) in estimated {
            let owner = unreadableOwners[pid] ?? Ownership.owner(of: pid)
            unreadableOwners[pid] = owner
            joules[owner, default: 0] += used * scale
            processes[pid] = (owner, used * scale / seconds, true)
        }
        unreadableOwners = unreadableOwners.filter { pids.contains($0.key) }
    }

    /// Reads `ps` again once ``cpuTimesInterval`` has passed, and works out each process's CPU use from the two readings.
    private func refreshCPURates(now: ContinuousClock.Instant) {
        // Soon after the first reading, so estimates show from the panel's first measurement; every few seconds after.
        let wait = cpuRates.isEmpty ? Self.firstCPUTimesInterval : Self.cpuTimesInterval
        if let taken = cpuTimesTakenAt, now - taken < wait { return }
        guard let times = CPUTimes.read() else { return }
        if let taken = cpuTimesTakenAt {
            let elapsed = (now - taken).seconds
            var rates: [pid_t: Double] = [:]
            for (pid, time) in times {
                // A process that's new, or a reused ID whose time went backwards, waits for the next reading.
                guard let before = cpuTimes[pid], time > before, elapsed > 0 else { continue }
                rates[pid] = (time - before) / elapsed
            }
            cpuRates = rates
        }
        cpuTimes = times
        cpuTimesTakenAt = now
    }

    /// The processes an app was responsible for in the last sample, hungriest first: the app itself, and the
    /// helpers, renderers and services it started. Nothing new is measured: it's the last sample, split up.
    public func processes(of responsiblePID: pid_t) -> [ProcessEnergy] {
        processes { $0 == responsiblePID }
    }

    /// The processes of all these owners together (a service with several, like Spotlight's indexers).
    public func processes(ofAny owners: Set<pid_t>) -> [ProcessEnergy] {
        processes { owners.contains($0) }
    }

    /// The processes whose owner isn't one of these: what no slice accounts for, for Display & System's breakdown.
    public func processes(notOf owners: Set<pid_t>, limit: Int) -> [ProcessEnergy] {
        Array(processes { !owners.contains($0) }.prefix(limit))
    }

    private func processes(where owner: (pid_t) -> Bool) -> [ProcessEnergy] {
        lastProcesses
            .filter { owner($0.value.responsible) }
            .map { pid, value in
                ProcessEnergy(
                    pid: pid, name: ProcessName.of(pid), watts: value.watts, isApp: pid == value.responsible, isEstimated: value.isEstimated)
            }
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

    /// The process's lifetime energy use in nanojoules, and when it started, or
    /// `nil` when we may not read them (processes of other users, for example).
    private static func usage(of pid: pid_t) -> (energy: UInt64, cpuTime: UInt64, started: UInt64)? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard result == 0 else { return nil }
        return (info.ri_energy_nj, info.ri_user_time &+ info.ri_system_time, info.ri_proc_start_abstime)
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
    /// Worked out from its CPU time, as its energy can't be read (one of macOS's or another user's).
    public let isEstimated: Bool

    public var id: pid_t { pid }

    /// Its name under its app's, without repeating the app: "Helper (Renderer)" for "Google Chrome Helper (Renderer)"
    /// under Google Chrome, which keeps the part that tells the helpers apart. The app's own process, and one named
    /// for something else (`cloudflared`), keep their names.
    public func shortName(inApp appName: String) -> String {
        guard !appName.isEmpty, name.hasPrefix(appName) else { return name }
        let rest = name.dropFirst(appName.count).trimmingCharacters(in: Self.separators)
        // "Safari" in "SafariBookmarksSyncAgent" is the start of a word, not the app's name.
        guard let first = name.dropFirst(appName.count).first, !first.isLetter, !rest.isEmpty else { return name }
        return rest
    }

    private static let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–_."))

    public init(pid: pid_t, name: String, watts: Double, isApp: Bool, isEstimated: Bool = false) {
        self.pid = pid
        self.name = name
        self.watts = watts
        self.isApp = isApp
        self.isEstimated = isEstimated
    }
}

/// A process's name from its executable's path, which isn't cut short at 16 or 32 characters like `proc_name`'s.
public enum ProcessName {
    public static func of(_ pid: pid_t) -> String {
        if let path = path(of: pid), let name = path.split(separator: "/").last, !name.isEmpty { return String(name) }
        var short = [CChar](repeating: 0, count: 64)
        proc_name(pid, &short, UInt32(short.count))
        let name = String(decoding: short.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? "\(pid)" : name
    }

    /// The process's executable, in full; `nil` when it may not be read.
    public static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

extension Duration {
    fileprivate var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
