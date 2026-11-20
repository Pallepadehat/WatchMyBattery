import Darwin
import Foundation
import Testing

@testable import BatteryKit

/// The sampler against the real kernel: work done in this process has to show up, credited to the app responsible for it.
@Suite(.tags(.system), .serialized)
struct EnergySamplingTests {
    /// Some virtual Macs don't count energy at all; there's nothing to measure there.
    static let countsEnergy: Bool = {
        let before = ownEnergy()
        burnCPU(for: .milliseconds(50))
        return (ownEnergy() ?? 0) > (before ?? .max)
    }()

    /// Running in a virtual machine, where macOS reports `kern.hv_vmm_present`.
    static let isVirtual: Bool = {
        var present: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &present, &size, nil, 0) == 0 && present == 1
    }()

    @Test func firstSampleIsOnlyABaseline() async {
        let sampler = ProcessEnergySampler()
        let (joules, seconds) = await sampler.sampleEnergy()
        #expect(joules.isEmpty)
        #expect(seconds == 0)
    }

    /// The GPU's energy and each process's GPU time, where the Mac reports them (Apple silicon does): readings that only
    /// grow, and something to share between, as WindowServer always uses the GPU. Virtual Macs (CI runners) have no GPU
    /// energy counter, so there's nothing to read there.
    @Test(.enabled(if: !isVirtual)) func theGPUIsReadOnAppleSilicon() throws {
        #if arch(arm64)
            let counter = try #require(GPUEnergyCounter())
            let first = try #require(counter.joules())
            let second = try #require(counter.joules())
            #expect(second >= first)
            #expect(!GPUEnergySampler().clients().isEmpty)
        #endif
    }

    @Test func resetStartsAfresh() async {
        let sampler = ProcessEnergySampler()
        _ = await sampler.sampleEnergy()
        await sampler.reset()
        let (joules, seconds) = await sampler.sampleEnergy()
        #expect(joules.isEmpty)
        #expect(seconds == 0)
    }

    @Test(.enabled(if: countsEnergy)) func creditsWorkToTheResponsibleApp() async throws {
        let sampler = ProcessEnergySampler()
        _ = await sampler.sampleEnergy()
        burnCPU(for: .milliseconds(300))
        let (joules, seconds) = await sampler.sampleEnergy()

        #expect(seconds >= 0.3 && seconds < 5)
        let responsible = Ownership.owner(of: getpid())
        let used = try #require(joules[responsible], "The work done here wasn't credited to process \(responsible)")
        // A core flat out for 0.3 s: well over a millijoule, and nowhere near what a whole Mac could use.
        #expect(used > 0.001)
        #expect(used < 100)
        // Nothing is credited twice: helpers are folded into the app responsible for them.
        #expect(joules.keys.allSatisfy { $0 > 0 })
    }

    @Test(.enabled(if: countsEnergy)) func wattsAreJoulesOverTime() async {
        let sampler = ProcessEnergySampler()
        _ = await sampler.sample()
        burnCPU(for: .milliseconds(200))
        let watts = await sampler.sample()
        let responsible = Ownership.owner(of: getpid())
        // One busy core: more than nothing, less than a whole Mac.
        #expect((watts[responsible] ?? 0) > 0)
        #expect(watts.values.allSatisfy { $0 >= 0 && $0 < 500 })
    }

    @Test func responsibilityIsStable() {
        let pid = getpid()
        #expect(Responsibility.responsiblePID(for: pid) == Responsibility.responsiblePID(for: pid))
        #expect(Responsibility.responsiblePID(for: pid) > 0)
    }

    // MARK: - Helpers

    static func ownEnergy() -> UInt64? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) }
        }
        return result == 0 ? info.ri_energy_nj : nil
    }
}

/// Keeps a core busy, so there's energy to measure.
func burnCPU(for duration: Duration) {
    let clock = ContinuousClock()
    let end = clock.now + duration
    var value: UInt64 = 0x1234_5678
    while clock.now < end {
        for _ in 0..<10_000 { value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }
    }
    withExtendedLifetime(value) {}
}

/// Against real processes: a command run by a shell is a program named for itself, and belongs with the command
/// that started it (the outermost one typed at a shell: when these tests run from a terminal, `swift test`).
@Suite(.tags(.system), .serialized)
struct OwnershipSystemTests {
    @Test func aCommandUnderAShellOwnsItself() async throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // `; true` keeps zsh from replacing itself with the command, as it does with a lone one.
        shell.arguments = ["-c", "/bin/sleep 5; true"]
        try shell.run()
        defer { shell.terminate() }
        // Wait for zsh to start the command.
        var command: pid_t?
        for _ in 0..<50 where command == nil {
            try await Task.sleep(for: .milliseconds(20))
            command = Self.children(of: shell.processIdentifier).first
        }
        let sleep = try #require(command)
        #expect(Ownership.isCommand(sleep))
        #expect(Ownership.owner(of: sleep) == Ownership.owner(of: shell.processIdentifier))
        #expect(CommandName.of(sleep) == "sleep")
        kill(sleep, SIGTERM)
    }

    private static func children(of parent: pid_t) -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = pids.withUnsafeMutableBytes { proc_listchildpids(parent, $0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(count, 0))))
    }
}

/// `ps`, run the way the sampler runs it: every process's CPU time, the kernel's and this one's among them.
@Suite(.tags(.system))
struct CPUTimesSystemTests {
    @Test func readsEveryProcess() throws {
        let times = try #require(CPUTimes.read())
        #expect(times.count > 50)
        #expect(times[1] != nil)  // launchd, root's, which only `ps` (set to run as root) can read
        #expect(times[getpid()] != nil)
    }

    @Test func aFailingProgramGivesNothing() {
        #expect(CPUTimes.run("/usr/bin/false", []) == nil)
        #expect(CPUTimes.run("/no/such/program", []) == nil)
        #expect(CPUTimes.run("/bin/echo", ["hi"]).map { String(decoding: $0, as: UTF8.self) } == "hi\n")
    }
}
