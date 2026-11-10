import AppKit
import BatteryKit
import OSLog
import Observation
import SwiftUI

/// Finds the apps using the most energy, while someone's looking.
///
/// Sampling runs only between ``start()`` and ``stop()`` (while the panel is
/// open), so the app costs next to nothing the rest of the time.
@Observable
final class AppUsageMonitor {
    /// The hungriest apps, hungriest first.
    private(set) var apps: [AppUsage] = []
    /// The whole Mac's power draw, smoothed. `nil` until the first reading.
    private(set) var systemWatts: Double?
    /// `true` from ``start()`` until the first measurement arrives.
    private(set) var isWarmingUp = false

    /// How many apps to list.
    var maximumApps = 4

    @ObservationIgnored private let sampler = ProcessEnergySampler()
    @ObservationIgnored private let systemPower = SystemPowerReader()
    @ObservationIgnored private var appPower = PowerSmoother<pid_t>()
    @ObservationIgnored private var systemPowerSmoother = SingleValueSmoother()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var appInfo = AppInfoCache()
    /// Apps we've asked to quit, hidden until they're gone (or give up quitting).
    @ObservationIgnored private var quitting: [pid_t: ContinuousClock.Instant] = [:]

    /// An app only makes the list when it draws at least this much.
    private static let minimumWatts = 0.02
    private static let interval: Duration = .seconds(2)
    /// The first reading comes quickly, so the panel fills in right away.
    private static let firstInterval: Duration = .milliseconds(500)

    func start() {
        guard task == nil else { return }
        isWarmingUp = apps.isEmpty
        task = Task { [weak self, sampler] in
            _ = await sampler.sample()  // the baseline
            var interval = Self.firstInterval
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                let readings = await sampler.sample()
                self?.update(with: readings)
                interval = Self.interval
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        Task { [sampler] in await sampler.reset() }
    }

    /// Asks the app to quit, the same as choosing Quit from its menu. Apps with
    /// unsaved work can still ask what to do with it.
    func quit(_ app: AppUsage) {
        guard let running = NSRunningApplication(processIdentifier: app.id) else { return }
        quitting[app.id] = .now
        apps.removeAll { $0.id == app.id }
        if !running.terminate() {
            Logger.app.notice("\(app.name, privacy: .public) refused to quit")
            quitting[app.id] = nil
        }
    }

    #if DEBUG
        /// Shows made-up apps, for previews.
        func preview(apps: [AppUsage], systemWatts: Double) {
            self.apps = apps
            self.systemWatts = systemWatts
        }
    #endif

    // MARK: - Measuring

    private func update(with readings: [pid_t: Double]) {
        appPower.add(readings)
        if let watts = systemPower.currentWatts() { systemPowerSmoother.add(watts) }
        systemWatts = systemPowerSmoother.value

        // Give apps that were asked to quit a few seconds before they may show up again.
        let now = ContinuousClock.now
        quitting = quitting.filter { pid, asked in
            now - asked < .seconds(8) && NSRunningApplication(processIdentifier: pid)?.isTerminated == false
        }

        var next: [AppUsage] = []
        for (pid, watts) in appPower.values.sorted(by: { $0.value > $1.value }) {
            guard next.count < maximumApps, watts >= Self.minimumWatts else { break }
            guard quitting[pid] == nil, let info = appInfo.info(for: pid) else { continue }
            next.append(
                AppUsage(
                    id: pid, name: info.name, bundleIdentifier: info.bundleIdentifier, icon: info.icon, tint: info.tint,
                    watts: watts))
        }
        appInfo.forget(except: Set(appPower.values.keys))

        // Keep the slices still while one is being dragged, so the drag isn't pulled out from under the pointer.
        if next != apps, !DragToQuitController.shared.isDragging { apps = next }
        isWarmingUp = false
    }
}

/// Names, icons and colours of running apps, looked up once per process.
private struct AppInfoCache {
    struct Info {
        let name: String
        let bundleIdentifier: String?
        let icon: NSImage
        let tint: Color
    }

    /// `nil` marks a process that isn't an app you could quit.
    private var cache: [pid_t: Info?] = [:]
    private var tints: [String: Color] = [:]

    mutating func info(for pid: pid_t) -> Info? {
        if let cached = cache[pid] { return cached }
        let info = lookUp(pid)
        cache[pid] = .some(info)
        return info
    }

    mutating func forget(except pids: Set<pid_t>) {
        if cache.count > pids.count * 2 + 32 { cache = cache.filter { pids.contains($0.key) } }
    }

    private mutating func lookUp(_ pid: pid_t) -> Info? {
        guard pid != ProcessInfo.processInfo.processIdentifier,
            let app = NSRunningApplication(processIdentifier: pid),
            Self.isQuittable(app),
            let name = app.localizedName,
            let icon = app.icon
        else { return nil }
        let key = app.bundleIdentifier ?? name
        let tint = tints[key] ?? IconTint.color(of: icon)
        tints[key] = tint
        return Info(name: name, bundleIdentifier: app.bundleIdentifier, icon: icon, tint: tint)
    }

    /// Apps you see and can quit: ones in the Dock, and menu bar apps that aren't part of macOS.
    private static func isQuittable(_ app: NSRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier ?? ""
        if alwaysRunning.contains(bundleID) { return false }
        switch app.activationPolicy {
        case .regular: return true
        case .accessory: return !bundleID.hasPrefix("com.apple.")
        default: return false
        }
    }

    /// Parts of macOS that would come straight back (or shouldn't go).
    private static let alwaysRunning: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.WindowManager",
    ]
}
