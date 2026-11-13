import AppKit
import BatteryKit
import OSLog
import Observation

/// Keeps ``accessories`` up to date with the Bluetooth accessories that are
/// connected, and says when headphones arrive, for the AirPods card.
///
/// macOS announces accessories connecting, disconnecting and (for AirPods
/// and others it publishes as power sources) their batteries changing, so
/// this costs nothing while nothing changes. Magic accessories' levels sit
/// in the HID registry, which doesn't announce changes, so they're also
/// read when the panel opens, after waking, and, only while one is
/// connected, every quarter of an hour, with plenty of leeway for macOS to
/// fold the wake-up into others. A read is a handful of IOKit calls.
@Observable
final class AccessoryMonitor {
    private(set) var accessories: [Accessory] = []

    /// Headphones just connected (not at launch, and not after a brief dropout).
    @ObservationIgnored var onArrival: (Accessory) -> Void = { _ in }

    @ObservationIgnored private var observer: AccessoryObserver?
    @ObservationIgnored private var arrivals = AccessoryArrivals()
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var slowRefresh: Task<Void, Never>?
    @ObservationIgnored private var followUp: Task<Void, Never>?
    /// The Magic accessories, searched for only when they come or go.
    @ObservationIgnored private let registry = AccessoryRegistry()
    @ObservationIgnored private var needsRescan = false
    @ObservationIgnored private var wakeToken: (any NSObjectProtocol)?

    private static let slowRefreshInterval: Duration = .seconds(15 * 60)

    // MARK: iPhone and iPad

    /// iPhones and iPads show along with the accessories (Settings › Accessories).
    var includesDevices = true {
        didSet {
            guard includesDevices != oldValue, !LaunchOptions.pretendsAccessories else { return }
            if includesDevices { startDevices() }
            publish(local)
        }
    }
    /// The accessories macOS itself knows about, before devices are added.
    @ObservationIgnored private var local: [Accessory] = []
    /// iPhones and iPads that trust this Mac, from their last reading.
    @ObservationIgnored private var devices: [Accessory] = []
    /// Every iPhone and iPad read lately, with when. An iPhone comes and goes from Wi‑Fi all the time (whenever it
    /// locks and sleeps), so one out of reach keeps showing its last reading, saying how old it is, for a day.
    @ObservationIgnored private var deviceCache: [String: CachedDevice] = AccessoryMonitor.loadDeviceCache()
    /// When each iPhone or iPad shown was last read, by id.
    private(set) var deviceReadDates: [String: Date] = [:]
    /// Reading the iPhones and iPads after the refresh button was clicked.
    private(set) var isRefreshingDevices = false
    /// The devices a refresh just couldn't reach, said in their rows for a few seconds.
    private(set) var unreachableDeviceIDs: Set<String> = []
    /// Tells the refresh in progress from one already over.
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var missedDeviceChange = false
    @ObservationIgnored private var unreachableReset: Task<Void, Never>?
    /// How long the refresh waits for a phone on Wi‑Fi before saying it couldn't reach it.
    private static let refreshTimeout: Duration = .seconds(12)
    /// The spinner shows at least this long, so a quick answer still looks like something happened.
    private static let refreshMinimum: Duration = .milliseconds(700)
    /// A reading older than this says how old it is, and offers to refresh.
    static let deviceStaleAfter: TimeInterval = 12 * 60
    private static let deviceCacheLifetime: TimeInterval = 24 * 60 * 60
    @ObservationIgnored private var deviceReader: AppleDeviceReader?
    @ObservationIgnored private var deviceRead: Task<Void, Never>?
    @ObservationIgnored private var deviceRefresh: Task<Void, Never>?
    @ObservationIgnored private var lastDeviceRead: ContinuousClock.Instant?
    /// A phone's level is read when it arrives, when the panel opens (at most this often), and every so often.
    private static let deviceReadInterval: Duration = .seconds(60)
    private static let deviceRefreshInterval: Duration = .seconds(10 * 60)

    func start() {
        guard observer == nil else { return }
        if LaunchOptions.pretendsAccessories {
            accessories = Self.samples
            return
        }
        let observer = AccessoryObserver(
            onChange: { [weak self] in self?.scheduleRefresh() },
            onDevicesChanged: { [weak self] in
                self?.scheduleRefresh(rescanning: true)
                self?.scheduleFollowUp()
            })
        observer.start()
        self.observer = observer
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(rescanning: true) }
        }
        registry.rescan()
        refresh()
        if includesDevices { startDevices() }
    }

    private func startDevices() {
        guard deviceReader == nil, !LaunchOptions.isIsolated, AppleDeviceReader.isAvailable else { return }
        let reader = AppleDeviceReader { [weak self] in
            Task { @MainActor in self?.readDevices(force: true) }
        }
        reader.start()
        deviceReader = reader
        // The last readings, until the devices answer.
        remember([])
    }

    /// Reads the iPhones and iPads now: the refresh button, for a reading that has grown old.
    func refreshDevices() {
        guard includesDevices, let reader = deviceReader, !isRefreshingDevices else { return }
        let wanted = Set(devices.filter { staleReadDate(of: $0) != nil }.map(\.id))
        let started = ContinuousClock.now
        isRefreshingDevices = true
        unreachableReset?.cancel()
        unreachableDeviceIDs = []
        // Its own read, which the reads on a timer or as the panel opens leave alone.
        deviceRead?.cancel()
        lastDeviceRead = .now
        refreshGeneration += 1
        let generation = refreshGeneration
        Task { [weak self] in
            let live = await reader.read()
            self?.finishRefresh(generation, live: live, wanted: wanted, started: started)
        }
        // A phone on Wi‑Fi that has gone to sleep can keep the read waiting a long while.
        Task { [weak self] in
            try? await Task.sleep(for: Self.refreshTimeout)
            self?.finishRefresh(generation, live: nil, wanted: wanted, started: started)
        }
    }

    /// The refresh's read answered (`live`), or it ran out of time (nil): whichever comes first ends the refresh.
    /// A reading that comes in after that is still kept.
    private func finishRefresh(_ generation: Int, live: [Accessory]?, wanted: Set<String>, started: ContinuousClock.Instant) {
        if let live, let reader = deviceReader {
            remember(live)
            updateDeviceRefresh(hasDevices: reader.hasDevices)
        }
        guard generation == refreshGeneration, isRefreshingDevices else { return }
        refreshGeneration += 1
        let unreachable = wanted.subtracting((live ?? []).map(\.id))
        Task { [weak self] in
            // The spinner shows a moment even when the answer is instant, so the click visibly did something.
            let elapsed = ContinuousClock.now - started
            if elapsed < Self.refreshMinimum { try? await Task.sleep(for: Self.refreshMinimum - elapsed) }
            guard let self else { return }
            self.isRefreshingDevices = false
            self.showUnreachable(unreachable)
            // A device came or went while it read: read once more, so it isn't missed.
            if self.missedDeviceChange {
                self.missedDeviceChange = false
                self.readDevices(force: true)
            }
        }
    }

    /// Says in these devices' rows that they couldn't be reached, for a few seconds.
    private func showUnreachable(_ ids: Set<String>) {
        unreachableDeviceIDs = ids
        guard !ids.isEmpty else { return }
        unreachableReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.unreachableDeviceIDs = []
        }
    }

    /// When an iPhone or iPad's level shown was read, if it's old enough to say so.
    func staleReadDate(of accessory: Accessory) -> Date? {
        guard accessory.kind.isDevice, let date = deviceReadDates[accessory.id] else { return nil }
        return Date.now.timeIntervalSince(date) > Self.deviceStaleAfter ? date : nil
    }

    /// Reads the phones' levels, unless that was done a moment ago.
    private func readDevices(force: Bool = false) {
        guard includesDevices, let reader = deviceReader else { return }
        // A refresh is reading already, and shows what it finds.
        if isRefreshingDevices {
            if force { missedDeviceChange = true }
            return
        }
        if !force, let lastDeviceRead, ContinuousClock.now - lastDeviceRead < Self.deviceReadInterval { return }
        lastDeviceRead = .now
        deviceRead?.cancel()
        deviceRead = Task { [weak self] in
            // A phone that just arrived needs a moment before it answers.
            if force { try? await Task.sleep(for: .seconds(2)) }
            let live = await reader.read()
            guard let self, !Task.isCancelled else { return }
            self.remember(live)
            self.updateDeviceRefresh(hasDevices: reader.hasDevices)
        }
    }

    /// Keeps what was just read, and shows it with the readings of devices out of reach for now.
    private func remember(_ live: [Accessory]) {
        let now = Date.now
        for device in live { deviceCache[device.id] = CachedDevice(device, readAt: now) }
        deviceCache = deviceCache.filter { now.timeIntervalSince($0.value.readAt) < Self.deviceCacheLifetime }
        Self.saveDeviceCache(deviceCache)

        let liveIDs = Set(live.map(\.id))
        let shown = deviceCache.values
            .map { cached in liveIDs.contains(cached.id) ? live.first { $0.id == cached.id }! : cached.accessory }
            .sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
        let dates = deviceCache.mapValues(\.readAt)
        if dates != deviceReadDates { deviceReadDates = dates }
        if shown != devices {
            devices = shown
            publish(local)
        }
    }

    private static let deviceCacheKey = "cachedDevices"

    private static func loadDeviceCache() -> [String: CachedDevice] {
        guard !LaunchOptions.isIsolated, !LaunchOptions.pretendsAccessories,
            let data = UserDefaults.standard.data(forKey: deviceCacheKey),
            let list = try? JSONDecoder().decode([CachedDevice].self, from: data)
        else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    private static func saveDeviceCache(_ cache: [String: CachedDevice]) {
        guard !LaunchOptions.isIsolated, let data = try? JSONEncoder().encode(Array(cache.values)) else { return }
        UserDefaults.standard.set(data, forKey: deviceCacheKey)
    }

    private func updateDeviceRefresh(hasDevices: Bool) {
        guard hasDevices != (deviceRefresh != nil) else { return }
        deviceRefresh?.cancel()
        deviceRefresh = nil
        guard hasDevices else { return }
        deviceRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.deviceRefreshInterval, tolerance: .seconds(2 * 60))
                guard !Task.isCancelled else { return }
                self?.readDevices(force: true)
            }
        }
    }

    /// The local accessories, then the devices, publishing only real changes.
    private func publish(_ local: [Accessory]) {
        self.local = local
        let next = local + (includesDevices ? devices : [])
        guard next != accessories else { return }
        if Set(next.map(\.id)) != Set(accessories.map(\.id)) { scheduleFollowUp() }
        log(next)
        accessories = next
    }

    /// Reads the accessories now, for example as the panel opens.
    func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        if LaunchOptions.pretendsAccessories { return }
        if needsRescan {
            needsRescan = false
            registry.rescan()
        }
        let next = AccessoryReader.read(registry: registry)
        // Only publish real changes, so the panel doesn't redraw for nothing.
        if next != local { publish(next) }
        for accessory in arrivals.update(with: next) { onArrival(accessory) }
        updateSlowRefresh()
        readDevices()
    }

    /// One more read a few seconds after something connects or goes: a new
    /// device's levels (a Magic accessory's especially) often come in a moment
    /// after the device itself.
    private func scheduleFollowUp() {
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.needsRescan = true
            self?.refresh()
        }
    }

    /// What's connected, for `log stream --predicate 'subsystem == "com.pallepadehat.WatchMyBattery"'`. Names stay private.
    private func log(_ accessories: [Accessory]) {
        let summary = accessories.map { accessory in
            let parts = accessory.parts.map { "\($0.role) \($0.percentage)%\($0.isCharging ? " charging" : "")" }.joined(separator: ", ")
            let source = accessory.id.hasPrefix("hid:") ? "registry" : accessory.id.hasPrefix("device:") ? "MobileDevice" : "power sources"
            return "\(accessory.kind) from \(source): \(parts)"
        }
        Logger.app.notice("Accessories: \(summary.isEmpty ? "none" : summary.joined(separator: "; "), privacy: .public)")
    }

    /// Notifications come in bursts (each earbud, then the case), so they're gathered into one read.
    private func scheduleRefresh(rescanning: Bool = false) {
        if rescanning { needsRescan = true }
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Reads now and then while a Magic accessory is connected, as its level changes without a word.
    private func updateSlowRefresh() {
        let needed = local.contains { $0.id.hasPrefix("hid:") }
        guard needed != (slowRefresh != nil) else { return }
        slowRefresh?.cancel()
        slowRefresh = nil
        guard needed else { return }
        slowRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.slowRefreshInterval, tolerance: .seconds(5 * 60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    #if DEBUG
        /// Shows made-up accessories, for previews.
        func preview(_ accessories: [Accessory], readDates: [String: Date] = [:]) {
            self.accessories = accessories
            deviceReadDates = readDates
        }

        func preview(refreshing: Bool = false, unreachable: Set<String> = []) {
            isRefreshingDevices = refreshing
            unreachableDeviceIDs = unreachable
        }
    #endif

    /// AirPods Pro, a Magic Keyboard running low, a Magic Mouse, a charging Magic Trackpad and an iPhone: `--pretend-accessories`.
    static let samples: [Accessory] = [
        Accessory(
            id: "sample-airpods", name: "AirPods Pro", kind: .earbuds,
            parts: [
                .init(role: .left, percentage: 82), .init(role: .right, percentage: 64),
                .init(role: .case, percentage: 47, isCharging: true),
            ], productID: 0x2027, vendorID: 0x004C),
        Accessory(
            id: "hid:keyboard", name: "Magic Keyboard", kind: .keyboard, parts: [.init(role: .single, percentage: 14)],
            vendorID: 0x004C),
        Accessory(
            id: "hid:mouse", name: "Magic Mouse", kind: .mouse, parts: [.init(role: .single, percentage: 71)], vendorID: 0x004C),
        Accessory(
            id: "hid:trackpad", name: "Magic Trackpad", kind: .trackpad, parts: [.init(role: .single, percentage: 58, isCharging: true)],
            vendorID: 0x004C),
        Accessory(
            id: "device:iphone", name: "iPhone", kind: .phone, parts: [.init(role: .single, percentage: 76, isCharging: true)],
            vendorID: 0x004C),
    ]
}

/// An iPhone or iPad's last reading, kept while it's out of reach.
private struct CachedDevice: Codable {
    let id: String
    let name: String
    let kind: Int
    let percentage: Int
    let readAt: Date

    init(_ accessory: Accessory, readAt: Date) {
        id = accessory.id
        name = accessory.name
        kind = accessory.kind.rawValue
        percentage = accessory.parts.first?.percentage ?? 0
        self.readAt = readAt
    }

    /// Not known to be charging: it can't be told from here.
    var accessory: Accessory {
        Accessory(
            id: id, name: name, kind: Accessory.Kind(rawValue: kind) ?? .phone,
            parts: [Accessory.Part(role: .single, percentage: percentage)], vendorID: 0x004C)
    }
}
