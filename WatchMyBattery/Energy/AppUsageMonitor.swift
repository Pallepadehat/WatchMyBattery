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
    /// The power no app accounts for: the display, graphics, Wi‑Fi and Bluetooth, and macOS's own processes. The
    /// Mac's whole draw, less what every app you could quit uses. `nil` until there's a reading of both.
    private(set) var systemSliceWatts: Double?

    /// The app whose processes the panel lists (its slice was clicked); `nil` for none.
    var inspectedApp: pid_t? {
        didSet {
            guard inspectedApp != oldValue else { return }
            inspectedProcesses = []
            refreshInspected()
        }
    }
    /// ``inspectedApp`` and the helpers it started, hungriest first, from the latest sample.
    private(set) var inspectedProcesses: [ProcessEnergy] = []

    /// An app that was asked to quit and is still open a moment later, most
    /// likely asking about unsaved changes.
    private(set) var refusal: QuitRefusal?

    /// How many apps to list.
    var maximumApps = 4
    /// Bundle identifiers of apps that never get a slice.
    var excludedApps: Set<String> = [] {
        didSet {
            guard excludedApps != oldValue else { return }
            apps.removeAll { $0.bundleIdentifier.map(excludedApps.contains) ?? false }
        }
    }

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
        inspectedApp = nil
        Task { [sampler] in await sampler.reset() }
    }

    /// Asks the app to quit, the same as choosing Quit from its menu. Apps with
    /// unsaved work can still ask what to do with it.
    ///
    /// If it's still running a moment later, its slice comes straight back and
    /// ``refusal`` says so, instead of the slice quietly reappearing later.
    func quit(_ app: AppUsage) {
        guard let running = NSRunningApplication(processIdentifier: app.id) else { return }
        if refusal?.id == app.id { refusal = nil }
        quitting[app.id] = .now
        apps.removeAll { $0.id == app.id }
        guard running.terminate() else {
            Logger.app.notice("\(app.name, privacy: .public) refused to quit")
            refuse(app, running: running)
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.quitGracePeriod)
            guard !running.isTerminated, self?.quitting[app.id] != nil else { return }
            self?.refuse(app, running: running)
        }
    }

    /// Quits an app straight away, without letting it ask about unsaved changes: for an app that's stopped
    /// responding, or one that wouldn't quit. Unsaved work is lost.
    func forceQuit(_ pid: pid_t) {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return }
        if refusal?.id == pid { refusal = nil }
        if inspectedApp == pid { inspectedApp = nil }
        quitting[pid] = .now
        apps.removeAll { $0.id == pid }
        if !running.forceTerminate() {
            Logger.app.error("Couldn't force \(running.localizedName ?? "an app", privacy: .public) to quit")
        }
    }

    /// Brings an app that wouldn't quit to the front, where its question is waiting.
    func showRefusedApp() {
        guard let refusal else { return }
        NSRunningApplication(processIdentifier: refusal.id)?.activate()
        self.refusal = nil
    }

    func dismissRefusal() {
        refusal = nil
    }

    /// How long an app gets to quit before we say it didn't.
    private static let quitGracePeriod: Duration = .seconds(1.5)

    private func refuse(_ app: AppUsage, running: NSRunningApplication) {
        quitting[app.id] = nil
        refusal = QuitRefusal(id: app.id, name: app.name, icon: app.icon)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        // Put the slice back right away, without waiting for the next reading.
        if !apps.contains(where: { $0.id == app.id }), apps.count < maximumApps {
            apps.append(app)
            apps.sort { $0.watts > $1.watts }
        }
        // Forget it once the app goes after all (the user saved or discarded their changes).
        let pid = app.id
        Task { [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(1))
                guard self?.refusal?.id == pid else { return }
                if running.isTerminated {
                    self?.refusal = nil
                    self?.apps.removeAll { $0.id == pid }
                    return
                }
            }
            if self?.refusal?.id == pid { self?.refusal = nil }
        }
    }

    /// Measures for a moment and returns the app using the most energy, for
    /// the low battery notification. Works while the panel is closed, too.
    func hungriestApp() async -> AppUsage? {
        let sampler = ProcessEnergySampler()
        _ = await sampler.sample()
        try? await Task.sleep(for: .seconds(2))
        let readings = await sampler.sample()
        var cache = AppInfoCache()
        for (pid, watts) in readings.sorted(by: { $0.value > $1.value }) where watts >= Self.minimumWatts {
            guard let info = cache.info(for: pid), !(info.bundleIdentifier.map(excludedApps.contains) ?? false) else { continue }
            return AppUsage(id: pid, name: info.name, bundleIdentifier: info.bundleIdentifier, icon: info.icon, tint: info.tint, watts: watts)
        }
        return nil
    }

    #if DEBUG
        /// Shows made-up apps, for previews.
        func preview(apps: [AppUsage], systemWatts: Double, refusal: QuitRefusal? = nil) {
            self.apps = apps
            self.systemWatts = systemWatts
            self.refusal = refusal
            systemSliceWatts = max(systemWatts - apps.reduce(0) { $0 + $1.watts } - 1.2, 0)
        }

        /// Shows made-up processes for the inspected app, for previews.
        func preview(inspecting pid: pid_t, processes: [ProcessEnergy]) {
            inspectedApp = pid
            inspectedProcesses = processes
        }
    #endif

    // MARK: - Measuring

    private func update(with readings: [pid_t: Double]) {
        appPower.add(readings)
        if let watts = systemPower.currentWatts() { systemPowerSmoother.add(watts) }
        // Every change redraws the panel, so only ones that would show are published (see `DisplayThreshold`).
        if DisplayThreshold.watts.isVisible(from: systemWatts, to: systemPowerSmoother.value) {
            systemWatts = systemPowerSmoother.value
        }

        // Give apps that were asked to quit a few seconds before they may show up again.
        let now = ContinuousClock.now
        quitting = quitting.filter { pid, asked in
            now - asked < .seconds(8) && NSRunningApplication(processIdentifier: pid)?.isTerminated == false
        }

        var next: [AppUsage] = []
        for (pid, watts) in appPower.values.sorted(by: { $0.value > $1.value }) {
            guard next.count < maximumApps, watts >= Self.minimumWatts else { break }
            guard quitting[pid] == nil, let info = appInfo.info(for: pid),
                !(info.bundleIdentifier.map(excludedApps.contains) ?? false)
            else { continue }
            next.append(
                AppUsage(
                    id: pid, name: info.name, bundleIdentifier: info.bundleIdentifier, icon: info.icon, tint: info.tint,
                    watts: watts))
        }
        appInfo.forget(except: Set(appPower.values.keys))
        updateSystemSlice()
        refreshInspected()

        // Keep the slices still while one is being dragged, so the drag isn't pulled out from under the pointer.
        if Self.differsVisibly(next, from: apps), !DragToQuitController.shared.isDragging { apps = next }
        // Its slice is gone (it quit, or others overtook it), so its processes go too.
        if let inspectedApp, !apps.contains(where: { $0.id == inspectedApp }) { self.inspectedApp = nil }
        if isWarmingUp { isWarmingUp = false }
    }

    /// The Mac's draw less every app's, apps hidden from the battery included: they use power, just not a slice.
    private func updateSystemSlice() {
        guard let total = systemWatts else { return }
        var apps = 0.0
        for (pid, watts) in appPower.values where appInfo.info(for: pid) != nil { apps += watts }
        let next = max(total - apps, 0)
        if DisplayThreshold.watts.isVisible(from: systemSliceWatts, to: next) { systemSliceWatts = next }
    }

    /// The inspected app's processes, from the sample just taken (nothing more is measured).
    private func refreshInspected() {
        guard let pid = inspectedApp else { return }
        Task { [weak self, sampler] in
            let processes = await sampler.processes(of: pid)
            guard let self, self.inspectedApp == pid else { return }
            let changed =
                processes.map(\.pid) != self.inspectedProcesses.map(\.pid)
                || zip(processes, self.inspectedProcesses).contains { DisplayThreshold.watts.isVisible(from: $1.watts, to: $0.watts) }
            if changed { self.inspectedProcesses = processes }
        }
    }

    /// Other apps, another order, or an app's power moved enough to show.
    private static func differsVisibly(_ next: [AppUsage], from shown: [AppUsage]) -> Bool {
        guard next.count == shown.count else { return true }
        return zip(next, shown).contains { new, old in
            new.id != old.id || new.name != old.name || DisplayThreshold.watts.isVisible(from: old.watts, to: new.watts)
        }
    }
}

/// An app that didn't quit when asked.
struct QuitRefusal: Equatable {
    let id: pid_t
    let name: String
    let icon: NSImage
}

/// Names, icons and colours of running apps, looked up once per process.
struct AppInfoCache {
    struct Info {
        let name: String
        let bundleIdentifier: String?
        let icon: NSImage
        let tint: Color
    }

    /// `nil` marks a process that isn't an app you could quit.
    private var cache: [pid_t: Info?] = [:]

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
        let tint = IconTint.color(of: icon, for: app.bundleIdentifier ?? "name:" + name)
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
