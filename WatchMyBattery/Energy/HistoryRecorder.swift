import AppKit
import BatteryKit
import OSLog
import Observation

/// Keeps the battery's history: the last 24 hours of its level and the apps
/// using it, for the panel's chart and the runaway app notification, and two
/// weeks of hourly summaries, for the ten-day chart and the insights.
///
/// The level comes free with every power source notification. Apps are
/// measured only on battery, and rarely: every five minutes, with a minute's
/// leeway so macOS can fold the wake-up into others. The kernel keeps
/// counting each process's energy in between, so a rare sample still sees
/// everything an app used, except apps that opened and quit between two
/// samples. A sample is a few hundred cheap system calls.
///
/// It's all kept with SwiftData (``HistoryStore``), which writes only what
/// changed: a row for each level change or sample, and the hour it touched.
@Observable
final class HistoryRecorder {
    private(set) var history: BatteryHistory
    private(set) var profile: UsageProfile

    /// Called after every energy sample, for the insights to take another look.
    @ObservationIgnored var didRecordSample: () -> Void = {}

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let sampler = ProcessEnergySampler()
    @ObservationIgnored private let systemPower = SystemPowerReader()
    @ObservationIgnored private var appInfo = AppInfoCache()
    @ObservationIgnored private var detector = RunawayDetector()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastSaved = Date.distantPast

    static let interval: Duration = .seconds(5 * 60)
    private static let leeway: Duration = .seconds(60)
    /// Level changes are saved at most this often; samples are saved as they come.
    private static let saveInterval: TimeInterval = 5 * 60

    init(storeURL: URL? = HistoryRecorder.defaultStoreURL, legacyFileURL: URL? = HistoryRecorder.legacyFileURL) {
        // A made-up battery shouldn't end up in the real history.
        let storeURL = LaunchOptions.pretendsCharging ? nil : storeURL
        store = HistoryStore.open(at: storeURL) { error in
            Logger.app.error("Couldn't open the battery history, starting it over: \(error.localizedDescription, privacy: .public)")
        }
        if store.isOnDisk, let legacyFileURL { Self.importLegacy(from: legacyFileURL, into: store) }
        history = store.history
        profile = store.profile
    }

    /// `~/Library/Application Support/WatchMyBattery/History.store`, or in the folder of an isolated run.
    nonisolated static var defaultStoreURL: URL? { supportFolder?.appending(path: "History.store") }

    /// Where the history was kept before 0.2.5, as a property list.
    nonisolated static var legacyFileURL: URL? { supportFolder?.appending(path: "History.plist") }

    nonisolated private static var supportFolder: URL? {
        if let folder = LaunchOptions.isolatedFolder { return folder }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appending(path: "WatchMyBattery")
    }

    /// Brings the old property list into the store, once, then removes it. Only into a store on disk, and only once
    /// it's safely there: if the store already has a history (after going back to an older version and forward again,
    /// say), the file is left alone rather than lost.
    private static func importLegacy(from url: URL, into store: HistoryStore) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let legacy = BatteryHistory.load(from: url)
        guard store.importLegacy(legacy) || legacy.isEmpty else {
            Logger.app.notice("Kept the old battery history file, as the store already has a history")
            return
        }
        do {
            try store.save()
            try FileManager.default.removeItem(at: url)
            Logger.app.notice("Moved the battery history into its new store")
        } catch {
            Logger.app.error("Couldn't move the battery history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func start(model: AppModel) {
        self.model = model
        observe()
    }

    /// Writes what hasn't been saved yet, before the app quits.
    func flush() {
        save(force: true)
    }

    /// Forgets the whole history, on disk too.
    func clear() {
        store.removeAll()
        detector.reset()
        // Start again from the current level.
        if let model { store.record(model.battery.snapshot) }
        publish()
        save(force: true)
    }

    /// The "new app" notification went out for an app, so it isn't sent again.
    func markNotifiedAsNew(_ key: String) {
        store.markNotifiedAsNew(key)
        publish()
        save(force: true)
    }

    /// Its line in the panel was dismissed, for good.
    func markDismissedAsNew(_ key: String) {
        store.markDismissedAsNew(key)
        publish()
        save(force: true)
    }

    /// Hands the store's latest to observers, only where it changed, so the panel redraws only then.
    private func publish() {
        if history != store.history { history = store.history }
        if profile != store.profile { profile = store.profile }
    }

    // MARK: - Watching the battery

    private func observe() {
        guard let model else { return }
        let (snapshot, isOn) = withObservationTracking {
            (model.battery.snapshot, model.settings.recordsHistory)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        guard isOn else {
            stopSampling(takingFinalSample: false)
            return
        }
        store.record(snapshot)
        publish()
        save(force: false)
        if snapshot.hasBattery, !snapshot.isPluggedIn {
            startSampling()
        } else {
            stopSampling(takingFinalSample: true)
        }
    }

    private func startSampling() {
        guard task == nil else { return }
        task = Task { [weak self, sampler] in
            _ = await sampler.sampleEnergy()  // the baseline
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval, tolerance: Self.leeway)
                guard !Task.isCancelled else { break }
                let (joules, seconds) = await sampler.sampleEnergy()
                self?.record(joules, seconds: seconds)
            }
        }
    }

    /// Plugged in: what apps used since the last sample was still battery, so it's counted too.
    private func stopSampling(takingFinalSample: Bool) {
        guard let task else { return }
        task.cancel()
        self.task = nil
        detector.reset()
        Task { [weak self, sampler] in
            let (joules, seconds) = await sampler.sampleEnergy()
            await sampler.reset()
            if takingFinalSample, seconds >= 30 { self?.record(joules, seconds: seconds, checksRunaways: false) }
        }
    }

    private func record(_ joules: [pid_t: Double], seconds: Double, checksRunaways: Bool = true) {
        guard seconds > 0 else { return }
        // Group by app, as several processes can share a bundle (two copies of an app, say).
        var byApp: [BatteryHistory.AppIdentity: Double] = [:]
        var pids: [String: pid_t] = [:]
        for (pid, value) in joules {
            guard let info = appInfo.info(for: pid) else { continue }
            let app = BatteryHistory.AppIdentity(name: info.name, bundleIdentifier: info.bundleIdentifier)
            byApp[app, default: 0] += value
            pids[app.key] = pid
        }
        appInfo.forget(except: Set(joules.keys))
        let systemWatts = systemPower.currentWatts()
        store.record(joules: byApp, seconds: seconds, systemWatts: systemWatts)
        publish()
        save(force: true)
        didRecordSample()

        guard checksRunaways, let sample = history.samples.last else { return }
        for key in detector.add(sample) {
            guard let app = history.apps[key], let pid = pids[key] else { continue }
            reportRunaway(app, pid: pid, systemWatts: systemWatts)
        }
    }

    private func reportRunaway(_ app: BatteryHistory.AppIdentity, pid: pid_t, systemWatts: Double?) {
        guard let model, model.settings.notifiesAboutRunawayApps,
            !model.settings.isExcluded(bundleIdentifier: app.bundleIdentifier),
            let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated
        else { return }
        // The app you're using isn't running away: you're asking it to work. Try again once you've moved on.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            detector.forget(app.key)
            return
        }
        let watts = detector.averageWatts(of: app.key) ?? 0
        let gained = Estimates(snapshot: model.battery.snapshot, systemWatts: systemWatts).timeGained(byQuitting: watts)
        Task { await model.notifier.notifyRunaway(app, pid: pid, minutes: Int(detector.window / 60), timeGained: gained) }
    }

    // MARK: - Saving

    /// Only what changed goes to disk, a few rows at a time, so it's done right here.
    private func save(force: Bool) {
        guard store.hasUnsavedChanges, force || Date().timeIntervalSince(lastSaved) >= Self.saveInterval else { return }
        lastSaved = Date()
        do {
            try store.save()
        } catch {
            Logger.app.error("Couldn't save the battery history: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
        /// Shows a made-up history, for previews.
        func preview(_ history: BatteryHistory, profile: UsageProfile = UsageProfile()) {
            self.history = history
            self.profile = profile
        }
    #endif
}
