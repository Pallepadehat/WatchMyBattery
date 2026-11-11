import AppKit
import BatteryKit
import OSLog
import Observation

/// Keeps the last 24 hours of the battery: its level, and which apps used
/// its energy, for the panel's history and the runaway app notification.
///
/// The level comes free with every power source notification. Apps are
/// measured only on battery, and rarely: every five minutes, with a minute's
/// leeway so macOS can fold the wake-up into others. The kernel keeps
/// counting each process's energy in between, so a rare sample still sees
/// everything an app used, except apps that opened and quit between two
/// samples. A sample is a few hundred cheap system calls.
@Observable
final class HistoryRecorder {
    private(set) var history: BatteryHistory

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let sampler = ProcessEnergySampler()
    @ObservationIgnored private let systemPower = SystemPowerReader()
    @ObservationIgnored private var appInfo = AppInfoCache()
    @ObservationIgnored private var detector = RunawayDetector()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private let fileURL: URL?

    static let interval: Duration = .seconds(5 * 60)
    private static let leeway: Duration = .seconds(60)
    /// Level changes are saved at most this often; samples are saved as they come.
    private static let saveInterval: TimeInterval = 5 * 60

    init(fileURL: URL? = HistoryRecorder.defaultFileURL) {
        var fileURL = fileURL
        #if DEBUG
            // A made-up battery shouldn't end up in the real history.
            if CommandLine.arguments.contains("--pretend-charging") { fileURL = nil }
        #endif
        self.fileURL = fileURL
        history = fileURL.map(BatteryHistory.load(from:)) ?? BatteryHistory()
    }

    /// `~/Library/Application Support/WatchMyBattery/History.plist`
    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "WatchMyBattery/History.plist")
    }

    func start(model: AppModel) {
        self.model = model
        observe()
    }

    /// Writes what hasn't been saved yet, before the app quits. Waits for it, as the app won't be around for long.
    func flush() {
        guard let fileURL else { return }
        let history = history
        Self.writer.sync { try? history.save(to: fileURL) }
    }

    /// Forgets the whole history, on disk too.
    func clear() {
        history.removeAll()
        detector.reset()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        // Start again from the current level.
        if let model { history.record(model.battery.snapshot) }
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
        history.record(snapshot)
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
        history.record(joules: byApp, seconds: seconds, systemWatts: systemWatts)
        save(force: true)

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

    private static let writer = DispatchQueue(label: "WatchMyBattery.history", qos: .utility)

    private func save(force: Bool) {
        guard let fileURL, force || Date().timeIntervalSince(lastSaved) >= Self.saveInterval else { return }
        lastSaved = Date()
        let history = history
        // One at a time, in order, off the main thread.
        Self.writer.async {
            do {
                try history.save(to: fileURL)
            } catch {
                Logger.app.error("Couldn't save the battery history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    #if DEBUG
        /// Shows a made-up history, for previews.
        func preview(_ history: BatteryHistory) {
            self.history = history
        }
    #endif
}
