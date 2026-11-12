import AppKit
import BatteryKit
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
    @ObservationIgnored private var wakeToken: (any NSObjectProtocol)?

    private static let slowRefreshInterval: Duration = .seconds(15 * 60)

    func start() {
        guard observer == nil else { return }
        if LaunchOptions.pretendsAccessories {
            accessories = Self.samples
            return
        }
        // Notifications come in bursts (each earbud, then the case), so they're gathered into one read.
        let observer = AccessoryObserver { [weak self] in self?.scheduleRefresh() }
        observer.start()
        self.observer = observer
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Reads the accessories now, for example as the panel opens.
    func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        if LaunchOptions.pretendsAccessories { return }
        let next = AccessoryReader.read()
        // Only publish real changes, so the panel doesn't redraw for nothing.
        if next != accessories { accessories = next }
        for accessory in arrivals.update(with: next) { onArrival(accessory) }
        updateSlowRefresh()
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Reads now and then while a Magic accessory is connected, as its level changes without a word.
    private func updateSlowRefresh() {
        let needed = accessories.contains { $0.id.hasPrefix("hid:") }
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
        func preview(_ accessories: [Accessory]) {
            self.accessories = accessories
        }
    #endif

    /// AirPods Pro, a Magic Keyboard running low, a Magic Mouse and a charging Magic Trackpad: `--pretend-accessories`.
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
    ]
}
