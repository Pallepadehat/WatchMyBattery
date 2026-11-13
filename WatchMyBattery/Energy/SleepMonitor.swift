import AppKit
import BatteryKit
import OSLog
import Observation

/// What the battery did while the Mac slept, and what's keeping it awake now.
///
/// "I closed the lid at 80% and woke up at 40%" usually has one of two causes: something kept the Mac from
/// sleeping at all, or something kept waking it. The first shows up as power assertions, which apps take and
/// macOS lists; the second as a sleep that used more than about 1% an hour.
///
/// macOS announces going to sleep and waking, so recording a sleep is two battery readings and costs nothing in
/// between. Assertions are read only while the panel is open.
@Observable
final class SleepMonitor {
    private(set) var log: SleepLog
    /// Processes keeping the Mac awake right now, read while the panel is open.
    private(set) var holders: [AwakeHolder] = []

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var tokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var asleepSince: (date: Date, level: Int, isPluggedIn: Bool)?
    @ObservationIgnored private var holdersTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = SleepMonitor.defaultFileURL) {
        // A made-up battery shouldn't end up in the real log.
        self.fileURL = LaunchOptions.pretendsCharging ? nil : fileURL
        log = self.fileURL.map(SleepLog.load(from:)) ?? SleepLog()
        log.trim()
    }

    /// `~/Library/Application Support/WatchMyBattery/Sleep.json`, or in the folder of an isolated run.
    nonisolated static var defaultFileURL: URL? {
        let folder =
            LaunchOptions.isolatedFolder
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appending(path: "WatchMyBattery")
        return folder?.appending(path: "Sleep.json")
    }

    func start(model: AppModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.willSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didWake() }
            },
        ]
    }

    /// The panel opened: read what's keeping the Mac awake, and keep reading every ten seconds while it's open.
    func panelDidOpen() {
        holdersTask?.cancel()
        holdersTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshHolders()
                try? await Task.sleep(for: .seconds(10), tolerance: .seconds(2))
            }
        }
    }

    func panelDidClose() {
        holdersTask?.cancel()
        holdersTask = nil
    }

    func clear() {
        log.removeAll()
        save()
    }

    // MARK: - Sleeping

    private func willSleep() {
        let snapshot = PowerSourceReader.read()
        guard snapshot.hasBattery else { return }
        asleepSince = (Date(), snapshot.percentage, snapshot.isPluggedIn)
    }

    private func didWake() {
        guard let since = asleepSince else { return }
        asleepSince = nil
        let wokeAt = Date()
        // The battery's level takes a moment to catch up after waking.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.finishSleep(since: since, wokeAt: wokeAt)
        }
    }

    private func finishSleep(since: (date: Date, level: Int, isPluggedIn: Bool), wokeAt: Date) {
        let snapshot = PowerSourceReader.read()
        guard snapshot.hasBattery else { return }
        let session = SleepSession(
            start: since.date, end: wokeAt, startLevel: since.level, endLevel: snapshot.percentage,
            wasPluggedIn: since.isPluggedIn || snapshot.isPluggedIn)
        guard log.record(session) else { return }
        save()
        Logger.app.notice(
            "Slept \(Int(session.duration / 60)) minutes, \(session.used.map { "used \($0)%" } ?? "on the adapter", privacy: .public)")
        if let model, model.settings.notifiesAboutSleepDrain, session.drain == .heavy, let used = session.used, used >= 5 {
            Task { await model.notifier.notifySleepDrain(session, typical: log.typicalPerHour) }
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try log.save(to: fileURL)
        } catch {
            Logger.app.error("Couldn't save the sleep log: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Awake

    private func refreshHolders() {
        var byApp: [String: AwakeHolder] = [:]
        for assertion in PowerAssertionReader.read() {
            let holder = AwakeHolder(assertion)
            guard holder.isRecognizable else { continue }
            if var existing = byApp[holder.id] {
                existing.merge(holder)
                byApp[holder.id] = existing
            } else {
                byApp[holder.id] = holder
            }
        }
        // What keeps the whole Mac awake first, then by name.
        let next = byApp.values.sorted {
            $0.effect != $1.effect ? $0.effect > $1.effect : $0.name.localizedLowercase < $1.name.localizedLowercase
        }
        if next != holders { holders = next }
    }

    #if DEBUG
        /// Shows a made-up log, for previews.
        func preview(_ log: SleepLog, holders: [AwakeHolder] = []) {
            self.log = log
            self.holders = holders
        }
    #endif
}

/// An app (or a command-line tool) keeping the Mac awake, with every reason it gave.
struct AwakeHolder: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let name: String
    let icon: NSImage?
    private(set) var reasons: [String]
    private(set) var effect: PowerAssertion.Effect
    private(set) var since: Date?
    /// An app that can be quit; a command-line tool or a part of macOS can't, from here.
    let isApp: Bool
    /// An app or tool people know, rather than one of macOS's own background processes.
    let isRecognizable: Bool
    /// What it's doing, as best macOS says.
    private(set) var activity: Activity

    enum Activity: Int, Comparable {
        case other, display, audio, microphone

        static func < (lhs: Activity, rhs: Activity) -> Bool { lhs.rawValue < rhs.rawValue }

        /// A symbol for it, small next to the app's name.
        var symbol: String {
            switch self {
            case .microphone: "mic.fill"
            case .audio: "speaker.wave.2.fill"
            case .display: "display"
            case .other: "moon.zzz.fill"
            }
        }
    }

    init(_ assertion: PowerAssertion) {
        // Parts of macOS hold some for an app (coreaudiod while it plays sound), and apps through their helpers:
        // either way, it's the app that's keeping the Mac awake.
        let app = OwningApp.of(pid: assertion.owner, processName: assertion.processName)
        id = app.id
        pid = assertion.owner
        name = app.name
        icon = app.icon
        let reason = Self.reason(for: assertion)
        reasons = reason.isEmpty ? [] : [reason]
        effect = assertion.effect
        since = assertion.since
        isApp = app.isApp
        isRecognizable = app.isRecognizable
        activity = Self.activity(of: assertion)
    }

    private static func activity(of assertion: PowerAssertion) -> Activity {
        if assertion.isRecordingAudio { return .microphone }
        if assertion.isPlayingAudio || assertion.reason.localizedCaseInsensitiveContains("audio") { return .audio }
        return assertion.effect == .keepsDisplayOn ? .display : .other
    }

    /// What it said it's for, or for macOS's own audio ones (named like
    /// "com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep"), what they mean.
    private static func reason(for assertion: PowerAssertion) -> String {
        if assertion.isRecordingAudio { return String(localized: "Using the microphone") }
        if assertion.isPlayingAudio { return String(localized: "Playing audio") }
        return assertion.reason
    }

    init(
        id: String, name: String, icon: NSImage? = nil, reasons: [String], effect: PowerAssertion.Effect, since: Date?,
        activity: Activity? = nil
    ) {
        self.id = id
        pid = 0
        self.name = name
        self.icon = icon
        isRecognizable = true
        self.reasons = reasons
        self.activity = activity ?? (effect == .keepsDisplayOn ? .display : .other)
        self.effect = effect
        self.since = since
        isApp = false
    }

    mutating func merge(_ other: AwakeHolder) {
        for reason in other.reasons where !reasons.contains(reason) { reasons.append(reason) }
        effect = max(effect, other.effect)
        activity = max(activity, other.activity)
        since = [since, other.since].compactMap(\.self).min()
    }

    /// The reason worth showing: one that reads like words. Many are identifiers meant for engineers
    /// ("com.apple.audio.…", "osservice<com.apple.akd(501)>…"), which say nothing to anyone else.
    var reason: String? {
        reasons.first { reason in
            reason.contains(" ") && !reason.contains("<") && !reason.hasPrefix("com.") && !reason.contains("(")
        }
    }

    static func == (lhs: AwakeHolder, rhs: AwakeHolder) -> Bool {
        lhs.id == rhs.id && lhs.reasons == rhs.reasons && lhs.effect == rhs.effect && lhs.since == rhs.since
    }
}

/// The app a process belongs to: the app itself, or the app a helper lives inside (a browser's or an Electron app's
/// helpers are apps of their own, inside the real one's bundle). A command-line tool or a part of macOS is itself.
private struct OwningApp {
    let id: String
    let name: String
    let icon: NSImage?
    let isApp: Bool
    /// Something people know: an app, a tool they ran, or a part of macOS with a name they'd recognise. macOS's own
    /// background processes (runningboardd, akd and the like) aren't, and there's nothing to do about them anyway.
    let isRecognizable: Bool

    /// Looked up once per process: finding the app and its icon means asking Launch Services and the file system,
    /// and the same few processes come up every ten seconds while the panel is open.
    private static var cache: [String: OwningApp] = [:]

    static func of(pid: pid_t, processName: String) -> OwningApp {
        let key = "\(pid):\(processName)"
        if let known = cache[key] { return known }
        let app = OwningApp(pid: pid, processName: processName)
        // Processes come and go; a few dozen entries is plenty.
        if cache.count > 64 { cache.removeAll() }
        cache[key] = app
        return app
    }

    private init(pid: pid_t, processName: String) {
        let path = Self.path(of: pid)
        let running = NSRunningApplication(processIdentifier: pid)
        if let running, running.activationPolicy == .regular {
            self.init(running)
        } else if let bundleURL = path.flatMap(Self.outermostApp), !Self.isSystem(bundleURL.path),
            let identifier = Bundle(url: bundleURL)?.bundleIdentifier
        {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
                self.init(app)
            } else {
                self.init(
                    id: identifier, name: FileManager.default.displayName(atPath: bundleURL.path).replacingOccurrences(of: ".app", with: ""),
                    icon: NSWorkspace.shared.icon(forFile: bundleURL.path), isApp: false, isRecognizable: true)
            }
        } else if let running, let bundleURL = running.bundleURL, !Self.isSystem(bundleURL.path) {
            self.init(running)
        } else if let known = Self.knownName(processName) {
            self.init(id: "process:" + processName, name: known, icon: nil, isApp: false, isRecognizable: true)
        } else {
            // A tool someone ran (from Homebrew, say) is worth showing; a part of macOS isn't.
            let isOwnTool = path.map { !Self.isSystem($0) } ?? false
            self.init(id: "process:" + processName, name: processName, icon: nil, isApp: false, isRecognizable: isOwnTool)
        }
    }

    private init(_ app: NSRunningApplication) {
        self.init(
            id: app.bundleIdentifier ?? "pid:\(app.processIdentifier)",
            name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "", icon: app.icon,
            isApp: app.activationPolicy == .regular, isRecognizable: true)
    }

    private init(id: String, name: String, icon: NSImage?, isApp: Bool, isRecognizable: Bool) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isApp = isApp
        self.isRecognizable = isRecognizable
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper" → Slack.app.
    private static func outermostApp(_ path: String) -> URL? {
        guard let range = path.range(of: ".app/") else { return nil }
        return URL(filePath: String(path[..<range.lowerBound]) + ".app", directoryHint: .isDirectory)
    }

    /// Where macOS keeps its own programs.
    private static func isSystem(_ path: String) -> Bool {
        ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// The parts of macOS people run into, named for what they do.
    private static func knownName(_ processName: String) -> String? {
        switch processName {
        case "coreaudiod": String(localized: "Sound")
        case "caffeinate": "caffeinate"
        case "backupd": String(localized: "Time Machine")
        case "softwareupdated": String(localized: "Software Update")
        case "sharingd": String(localized: "AirDrop & Sharing")
        case "mds", "mds_stores", "mdworker": String(localized: "Spotlight")
        default: nil
        }
    }
}
