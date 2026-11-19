import Darwin
import Foundation
import IOKit

/// The graphics card's part of each process's power, which the kernel's per-process energy totals leave out: they
/// count the CPU only, so a game, a video call or a browser full of animations looked lighter than it is.
///
/// Two readings, neither of which needs a permission:
/// - the GPU's energy, from the same energy model `powermetrics` reads (IOReport's "GPU Energy" channel), and
/// - how long the GPU worked for each process, which the graphics driver keeps for every process that talks to it
///   (`AppUsage` › `accumulatedGPUTime` on each of the accelerator's user clients).
///
/// The GPU's energy is shared out by that time. Where either is missing (Intel Macs, or a macOS that moved them)
/// there's simply no GPU share, and processes are measured by their CPU alone, as before.
///
/// Not thread-safe: ``ProcessEnergySampler`` owns one and calls it from its own actor.
final class GPUEnergySampler {
    private let counter = GPUEnergyCounter()
    /// Each accelerator client's GPU time last time, by its registry entry ID (a client is one connection; an app
    /// can have several, and they come and go).
    private var previousClients: [UInt64: GPUClient] = [:]
    private var previousEnergy: Double?

    /// Whether this Mac reports the GPU's energy at all.
    var isAvailable: Bool { counter != nil }

    /// Joules of GPU energy used by each process since the last call, keyed by the process that opened the
    /// connection to the GPU (WindowServer, an app, or one of its helpers). The first call only takes a baseline.
    func sample() -> [pid_t: Double] {
        guard let counter else { return [:] }
        let energy = counter.joules()
        let clients = self.clients()
        defer {
            previousEnergy = energy
            previousClients = clients
        }
        guard let energy, let previousEnergy, energy > previousEnergy else { return [:] }
        return Self.share(joules: energy - previousEnergy, now: clients, before: previousClients)
    }

    func reset() {
        previousEnergy = nil
        previousClients = [:]
        creators = [:]
    }

    /// `joules` shared out by each process's GPU time between the two readings. A client that wasn't there before
    /// opened since, so all of its time counts; a client that's gone took its time with it, which is lost (a sample is
    /// two seconds in the panel, so that's rare and small).
    static func share(joules: Double, now: [UInt64: GPUClient], before: [UInt64: GPUClient]) -> [pid_t: Double] {
        var time: [pid_t: Double] = [:]
        var total = 0.0
        for (id, client) in now {
            let earlier = before[id].flatMap { $0.pid == client.pid ? $0.nanoseconds : nil } ?? 0
            guard client.nanoseconds > earlier else { continue }
            let worked = Double(client.nanoseconds - earlier)
            time[client.pid, default: 0] += worked
            total += worked
        }
        guard total > 0, joules > 0 else { return [:] }
        return time.mapValues { joules * $0 / total }
    }

    /// One connection to the GPU: the process that opened it and how long the GPU has worked for it, all told.
    struct GPUClient: Equatable {
        var pid: pid_t
        var nanoseconds: UInt64
    }

    /// Which process opened each client. That never changes for a client, so it's read once, not every sample.
    private var creators: [UInt64: pid_t] = [:]

    /// Every GPU client that has used the GPU at all, by registry entry ID: one registry read for each, and one more
    /// the first time it's seen. Its values are read as they come, without making Swift dictionaries of them.
    func clients() -> [UInt64: GPUClient] {
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(accelerators) }

        var clients: [UInt64: GPUClient] = [:]
        var seen: [UInt64: pid_t] = [:]
        while case let accelerator = IOIteratorNext(accelerators), accelerator != IO_OBJECT_NULL {
            defer { IOObjectRelease(accelerator) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != IO_OBJECT_NULL {
                defer { IOObjectRelease(child) }
                guard let usage = Self.property(child, "AppUsage") as? NSArray, usage.count > 0 else { continue }
                var nanoseconds: UInt64 = 0
                for case let entry as NSDictionary in usage {
                    nanoseconds &+= (entry["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0
                }
                var id: UInt64 = 0
                guard nanoseconds > 0, IORegistryEntryGetRegistryEntryID(child, &id) == KERN_SUCCESS else { continue }
                let pid =
                    creators[id]
                    ?? (Self.property(child, "IOUserClientCreator") as? String).flatMap(Self.pid(fromCreator:))
                guard let pid else { continue }
                seen[id] = pid
                clients[id] = GPUClient(pid: pid, nanoseconds: nanoseconds)
            }
        }
        creators = seen
        return clients
    }

    /// "pid 398, WindowServer" → 398.
    static func pid(fromCreator creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return pid_t(digits).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// The GPU's running energy total, from IOReport's energy model: a library that's part of macOS but not of its public
/// SDK, so it's looked up at runtime, and its absence just means no GPU readings. Subscribes to the one channel it
/// needs, so a reading takes a fraction of a millisecond.
final class GPUEnergyCounter {
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription =
        @convention(c) (
            UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?
        ) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamples = @convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias IntegerValue = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamples
    private let integerValue: IntegerValue
    private let subscription: CFTypeRef
    private let channels: CFMutableDictionary
    /// Joules per unit the channel counts in.
    private let scale: Double

    static let channelName = "GPU Energy"

    init?() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW | RTLD_LOCAL),
            let copyChannels = dlsym(library, "IOReportCopyChannelsInGroup"),
            let createSubscription = dlsym(library, "IOReportCreateSubscription"),
            let createSamples = dlsym(library, "IOReportCreateSamples"),
            let channelName = dlsym(library, "IOReportChannelGetChannelName"),
            let unitLabel = dlsym(library, "IOReportChannelGetUnitLabel"),
            let integerValue = dlsym(library, "IOReportSimpleGetIntegerValue")
        else { return nil }
        let name = unsafeBitCast(channelName, to: ChannelString.self)
        let unit = unsafeBitCast(unitLabel, to: ChannelString.self)

        guard
            let group = unsafeBitCast(copyChannels, to: CopyChannelsInGroup.self)("Energy Model" as CFString, nil, 0, 0, 0)?
                .takeRetainedValue() as? [String: Any],
            let all = group["IOReportChannels"] as? [NSDictionary],
            let gpu = all.first(where: { (name($0 as CFDictionary)?.takeUnretainedValue() as String?) == Self.channelName }),
            let scale = Self.joules(perUnit: unit(gpu as CFDictionary)?.takeUnretainedValue() as String?)
        else { return nil }

        let wanted = NSMutableDictionary(dictionary: group)
        wanted["IOReportChannels"] = [gpu]
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard
            let subscription = unsafeBitCast(createSubscription, to: CreateSubscription.self)(
                nil, wanted as CFMutableDictionary, &subscribed, 0, nil)?.takeRetainedValue(),
            let channels = subscribed?.takeRetainedValue()
        else { return nil }

        self.createSamples = unsafeBitCast(createSamples, to: CreateSamples.self)
        self.integerValue = unsafeBitCast(integerValue, to: IntegerValue.self)
        self.subscription = subscription
        self.channels = channels
        self.scale = scale
    }

    /// The GPU's energy since some point in the past, in joules; only the difference between two readings means
    /// anything.
    func joules() -> Double? {
        guard let samples = createSamples(subscription, channels, nil)?.takeRetainedValue() as? [String: Any],
            let channels = samples["IOReportChannels"] as? [NSDictionary], !channels.isEmpty
        else { return nil }
        let total = channels.reduce(Int64(0)) { $0 &+ integerValue($1 as CFDictionary, 0) }
        return Double(total) * scale
    }

    static func joules(perUnit unit: String?) -> Double? {
        switch unit?.trimmingCharacters(in: .whitespaces) {
        case "nJ": 1e-9
        case "uJ", "µJ": 1e-6
        case "mJ": 1e-3
        case "J": 1
        default: nil
        }
    }
}
