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

    @Test func firstSampleIsOnlyABaseline() async {
        let sampler = ProcessEnergySampler()
        let (joules, seconds) = await sampler.sampleEnergy()
        #expect(joules.isEmpty)
        #expect(seconds == 0)
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
        let responsible = Responsibility.responsiblePID(for: getpid())
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
        let responsible = Responsibility.responsiblePID(for: getpid())
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
