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
    /// What the Mac is getting from the charger right now, smoothed: zero on battery, `nil` until the first reading or
    /// on a Mac that doesn't say. Not the charger's rating: a 100 W charger gives a Mac drawing 7 W about 7 W.
    private(set) var chargerWatts: Double?
    /// `true` from ``start()`` until the first measurement arrives.
    private(set) var isWarmingUp = false
    /// The power no app accounts for: the display, graphics, Wi‑Fi and Bluetooth, and macOS's own processes. The
    /// Mac's whole draw, less what every app you could quit uses. `nil` until there's a reading of both.
    private(set) var systemSliceWatts: Double?

    /// The app whose processes the panel lists (its slice was clicked); `nil` for none. It stays until it's closed or
    /// the app quits, even once others overtake it and its slice is gone: you asked to look at it.
    var inspected: AppUsage? {
        didSet {
            guard inspected?.id != oldValue?.id else { return }
            if inspected != nil { isInspectingSystem = false }
            if inspected?.name != oldValue?.name || inspected?.kind != oldValue?.kind { inspectedProcesses = [] }
            refreshInspected()
        }
    }
    /// Display & System's card is open.
    var isInspectingSystem = false {
        didSet {
            guard isInspectingSystem != oldValue else { return }
            if isInspectingSystem {
                inspected = nil
                if let systemSliceWatts { refreshSystemBreakdown(slice: systemSliceWatts) }
            } else {
                systemBreakdown = nil
            }
        }
    }
    /// What Display & System is made of, while its card is open.
    private(set) var systemBreakdown: SystemBreakdown?
    /// Every process with a slice of its own (or one that's hidden), for telling what's left for Display & System.
    @ObservationIgnored private var sliceOwners: Set<pid_t> = []

    /// ``inspected``'s process ID.
    var inspectedApp: pid_t? { inspected?.id }
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
    @ObservationIgnored private var chargerPowerSmoother = SingleValueSmoother()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var appInfo = AppInfoCache()
    /// Apps we've asked to quit, hidden until they're gone (or give up quitting).
    @ObservationIgnored private var quitting: [pid_t: ContinuousClock.Instant] = [:]

    /// An app only gets a slice when it draws at least this much: less is a rounding error next to the display, and a
    /// slice reading "<0.1 W" or "costs less than a minute" tells you nothing you could act on.
    private static let minimumWatts = 0.1
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
        inspected = nil
        isInspectingSystem = false
        chargerPowerSmoother.reset()
        chargerWatts = nil
        Task { [sampler] in await sampler.reset() }
    }

    /// Asks the app to quit, the same as choosing Quit from its menu. Apps with
    /// unsaved work can still ask what to do with it.
    ///
    /// If it's still running a moment later, its slice comes straight back and
    /// ``refusal`` says so, instead of the slice quietly reappearing later.
    func quit(_ app: AppUsage) {
        guard app.canQuit, let running = RunningProgram(pid: app.id, isApp: app.isApp) else { return }
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
        let known = (apps + [inspected].compactMap { $0 }).first { $0.id == pid }
        let isApp = known?.isApp ?? (refusal?.id == pid ? refusal?.isApp : nil) ?? true
        guard let running = RunningProgram(pid: pid, isApp: isApp) else { return }
        if refusal?.id == pid { refusal = nil }
        if inspected?.id == pid { inspected = nil }
        quitting[pid] = .now
        apps.removeAll { $0.id == pid }
        if !running.forceTerminate() {
            Logger.app.error("Couldn't force process \(pid, privacy: .public) to quit")
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

    private func refuse(_ app: AppUsage, running: RunningProgram) {
        quitting[app.id] = nil
        refusal = QuitRefusal(id: app.id, name: app.name, icon: app.icon, isApp: app.isApp)
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
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(500))
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
            guard info.kind != .macOS else { continue }
            return AppUsage(
                id: pid, name: info.name, bundleIdentifier: info.bundleIdentifier, icon: info.icon, tint: info.tint, watts: watts,
                kind: info.kind, label: info.label)
        }
        return nil
    }

    #if DEBUG
        /// Shows made-up apps, for previews.
        func preview(apps: [AppUsage], systemWatts: Double, chargerWatts: Double? = nil, refusal: QuitRefusal? = nil) {
            self.apps = apps
            self.systemWatts = systemWatts
            self.chargerWatts = chargerWatts
            self.refusal = refusal
            systemSliceWatts = max(systemWatts - apps.reduce(0) { $0 + $1.watts } - 1.2, 0)
        }

        /// Shows Display & System's card, for previews.
        func preview(system breakdown: SystemBreakdown) {
            isInspectingSystem = true
            systemBreakdown = breakdown
        }

        /// Shows made-up processes for the inspected app, for previews.
        func preview(inspecting pid: pid_t, processes: [ProcessEnergy]) {
            inspected = apps.first { $0.id == pid }
            inspectedProcesses = processes
        }
    #endif

    // MARK: - Measuring

    private func update(with readings: [pid_t: Double]) {
        appPower.add(readings)
        let flow = systemPower.currentFlow()
        if let flow { systemPowerSmoother.add(flow.systemWatts) }
        if let charger = flow?.chargerWatts {
            // Nothing coming in (on battery, or the charger's held back) is taken as it is, and so is the first watt after
            // it: easing from zero would read, for a few seconds after plugging in, as the battery making up for the charger.
            if charger == 0 || chargerPowerSmoother.value == 0 { chargerPowerSmoother.reset() }
            chargerPowerSmoother.add(charger)
        } else {
            chargerPowerSmoother.reset()
        }
        // Every change redraws the panel, so only ones that would show are published (see `DisplayThreshold`).
        if DisplayThreshold.watts.isVisible(from: systemWatts, to: systemPowerSmoother.value) {
            systemWatts = systemPowerSmoother.value
        }
        if DisplayThreshold.watts.isVisible(from: chargerWatts, to: chargerPowerSmoother.value) {
            chargerWatts = chargerPowerSmoother.value
        }

        // Give apps that were asked to quit a few seconds before they may show up again.
        let now = ContinuousClock.now
        quitting = quitting.filter { pid, asked in
            now - asked < .seconds(8) && RunningProgram.isRunning(pid)
        }

        // Every owner with a slice of its own. A part of macOS made of several processes (Spotlight's indexers) is one
        // slice, named for it, standing for all of them.
        var candidates: [AppUsage] = []
        var services: [String: Int] = [:]
        for (pid, watts) in appPower.values {
            guard quitting[pid] == nil, let info = appInfo.info(for: pid),
                !(info.bundleIdentifier.map(excludedApps.contains) ?? false)
            else { continue }
            if info.kind == .macOS, info.bundleIdentifier == nil, let index = services[info.name] {
                candidates[index].watts += watts
                candidates[index].members.append(pid)
                continue
            }
            if info.kind == .macOS, info.bundleIdentifier == nil { services[info.name] = candidates.count }
            candidates.append(
                AppUsage(
                    id: pid, name: info.name, bundleIdentifier: info.bundleIdentifier, icon: info.icon, tint: info.tint, watts: watts,
                    kind: info.kind, label: info.label, detail: info.detail, members: [pid]))
        }
        // The slice keeps the ID of the service's busiest process, so it stays the same slice from one sample to the next.
        for index in candidates.indices where candidates[index].members.count > 1 {
            let members = candidates[index].members.sorted { (appPower.values[$0] ?? 0) > (appPower.values[$1] ?? 0) }
            let first = candidates[index]
            candidates[index] = AppUsage(
                id: members[0], name: first.name, bundleIdentifier: first.bundleIdentifier, icon: first.icon, tint: first.tint, watts: first.watts,
                kind: first.kind, label: first.label, detail: first.detail, members: members)
        }
        let next = Array(
            candidates.filter { $0.watts >= Self.minimumWatts }.sorted { $0.watts > $1.watts }.prefix(maximumApps))
        sliceOwners = Set(candidates.flatMap(\.owners))
        appInfo.forget(except: Set(appPower.values.keys))
        updateSystemSlice()
        refreshInspected()

        // Keep the slices still while one is being dragged, so the drag isn't pulled out from under the pointer.
        if Self.differsVisibly(next, from: apps), !DragToQuitController.shared.isDragging { apps = next }
        // Its card closes when the app has quit, not when others overtake it.
        if let inspected, inspected.canQuit, !RunningProgram.isRunning(inspected.id) { self.inspected = nil }
        // A part of macOS keeps its card, standing for whichever of its processes is busiest now.
        if let inspected, inspected.kind == .macOS, let current = apps.first(where: { $0.name == inspected.name && $0.kind == .macOS }),
            current.owners != inspected.owners
        {
            self.inspected = current
        }
        if isWarmingUp { isWarmingUp = false }
    }

    /// The Mac's draw less everything with a slice of its own, hidden ones included: they use power, just not a slice.
    private func updateSystemSlice() {
        guard let total = systemWatts else { return }
        var named = 0.0
        for (pid, watts) in appPower.values where appInfo.info(for: pid) != nil { named += watts }
        let next = max(total - named, 0)
        if DisplayThreshold.watts.isVisible(from: systemSliceWatts, to: next) { systemSliceWatts = next }
        refreshSystemBreakdown(slice: next)
    }

    /// What's in Display & System, while its card is open: macOS's processes that have no slice of their own, by name,
    /// and what's left once they're counted, the screen and the rest of the hardware, which aren't measured part by part.
    private func refreshSystemBreakdown(slice: Double) {
        guard isInspectingSystem else { return }
        let owners = sliceOwners
        Task { [weak self, sampler] in
            let processes = await sampler.processes(notOf: owners, limit: 40)
            guard let self, self.isInspectingSystem else { return }
            let listed = Array(processes.filter { $0.watts >= 0.01 }.prefix(6))
            let processWatts = processes.reduce(0) { $0 + $1.watts }
            let next = SystemBreakdown(processes: listed, hardwareWatts: max(slice - processWatts, 0))
            if next.differsVisibly(from: self.systemBreakdown) { self.systemBreakdown = next }
        }
    }

    /// The inspected app's processes, from the sample just taken (nothing more is measured).
    private func refreshInspected() {
        guard let inspected else { return }
        let pid = inspected.id
        let owners = inspected.owners
        Task { [weak self, sampler] in
            let processes = await sampler.processes(ofAny: owners)
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

/// Display & System, taken apart as far as it can be.
struct SystemBreakdown: Equatable {
    /// macOS's processes with no slice of their own, busiest first.
    var processes: [ProcessEnergy]
    /// What's left: the screen, Wi‑Fi, memory and the rest of the hardware, which macOS doesn't report part by part.
    var hardwareWatts: Double

    func differsVisibly(from other: SystemBreakdown?) -> Bool {
        guard let other else { return true }
        return processes.map(\.pid) != other.processes.map(\.pid)
            || zip(processes, other.processes).contains { DisplayThreshold.watts.isVisible(from: $1.watts, to: $0.watts) }
            || DisplayThreshold.watts.isVisible(from: other.hardwareWatts, to: hardwareWatts)
    }
}

/// An app (or program) that didn't quit when asked.
struct QuitRefusal: Equatable {
    let id: pid_t
    let name: String
    let icon: NSImage
    var isApp = true
}

/// Something to quit: an app, asked the way its Quit menu item would, or a program that isn't one, sent the signal
/// Ctrl-C or `kill` would send. Remembers when the process started, as process IDs get reused.
struct RunningProgram {
    let pid: pid_t
    private let app: NSRunningApplication?
    private let started: UInt64?

    init?(pid: pid_t, isApp: Bool) {
        self.pid = pid
        if isApp {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            self.app = app
            started = nil
        } else {
            guard let started = Self.startTime(of: pid) else { return nil }
            app = nil
            self.started = started
        }
    }

    var isTerminated: Bool {
        if let app { return app.isTerminated }
        return Self.startTime(of: pid) != started
    }

    /// Quit, letting it tidy up: an app may ask about unsaved changes, a program gets SIGTERM. A command that leads its
    /// own process group (one typed at a shell does) is stopped along with what it started, like Ctrl-C would.
    func terminate() -> Bool {
        if let app { return app.terminate() }
        return signal(SIGTERM)
    }

    /// Quit straight away, losing unsaved work.
    func forceTerminate() -> Bool {
        if let app { return app.forceTerminate() }
        return signal(SIGKILL)
    }

    private func signal(_ signal: Int32) -> Bool {
        guard !isTerminated else { return true }
        if getpgid(pid) == pid { return killpg(pid, signal) == 0 }
        return kill(pid, signal) == 0
    }

    /// Whether the process is still there (as any process: an app or not).
    static func isRunning(_ pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) { return !app.isTerminated }
        return startTime(of: pid) != nil
    }

    private static func startTime(of pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_status != SZOMB else { return nil }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }
}

/// Names, icons and colours of what gets a slice (apps, programs that aren't apps, and parts of macOS), looked up once
/// per process.
@MainActor
struct AppInfoCache {
    struct Info {
        let name: String
        let bundleIdentifier: String?
        let icon: NSImage
        let tint: Color
        var kind: AppUsage.Kind = .app
        var label: String? = nil
        var detail: String? = nil
    }

    /// `nil` marks a process with no slice of its own: it stays in Display & System.
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
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid) {
            guard let name = app.localizedName, let icon = app.icon else { return nil }
            let tint = IconTint.color(of: icon, for: app.bundleIdentifier ?? "name:" + name)
            // Finder, the Dock and the like: part of macOS, with their own icons, but not to be quit.
            if Self.alwaysRunning.contains(app.bundleIdentifier ?? "") {
                return Info(name: name, bundleIdentifier: app.bundleIdentifier, icon: icon, tint: tint, kind: .macOS)
            }
            if Self.isQuittable(app) { return Info(name: name, bundleIdentifier: app.bundleIdentifier, icon: icon, tint: tint) }
            // An agent of macOS's own (Control Center, Notification Center): one of its services, if it's a known one.
        }
        if let service = Self.service(pid) { return service }
        return Self.program(pid)
    }

    /// A part of macOS worth a slice of its own (see ``MacOSServices``).
    private static func service(_ pid: pid_t) -> Info? {
        guard let service = MacOSServices.service(forProcessNamed: ProcessName.of(pid)) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: service.iconPath)
        return Info(
            name: service.name, bundleIdentifier: nil, icon: icon, tint: IconTint.color(of: icon, for: "service:" + service.name),
            kind: .macOS, detail: service.detail)
    }

    /// A program of yours that isn't an app: a command typed in a terminal or sent to the background from one, wherever
    /// it lives, or one running by itself that isn't part of macOS (Docker's engine, a VM, `ollama serve`, a Homebrew
    /// service). One inside an app's bundle, or named like an installed app, takes that app's icon ("Docker"); others
    /// get macOS's plain icon for a program, and their name written in their slice. Other users' processes, and
    /// macOS's own that aren't a known service, stay in Display & System.
    private static func program(_ pid: pid_t) -> Info? {
        guard Self.owner(of: pid) == getuid(), let path = ProcessName.path(of: pid),
            Ownership.isCommand(pid) || Ownership.isStartedByAnother(pid) || !Self.isPartOfMacOS(path)
        else { return nil }
        if let bundle = Self.enclosingApp(of: path) {
            let name = FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: "")
            let icon = NSWorkspace.shared.icon(forFile: bundle)
            return Info(
                name: name, bundleIdentifier: nil, icon: icon, tint: IconTint.color(of: icon, for: "name:" + name), kind: .program)
        }
        guard let name = CommandName.of(pid), !name.isEmpty else { return nil }
        if let icon = InstalledApps.icon(forCommand: name) {
            return Info(name: name, bundleIdentifier: nil, icon: icon, tint: IconTint.color(of: icon, for: "name:" + name), kind: .program)
        }
        // No icon of its own: the icon of the terminal (or editor) it runs in, which says where to find it, or macOS's own
        // for a program, as Finder shows it.
        let host = NSRunningApplication(processIdentifier: Ownership.responsiblePID(of: pid))
        let hosted = host.flatMap { $0.processIdentifier != pid && $0.activationPolicy == .regular ? $0 : nil }
        return Info(
            name: name, bundleIdentifier: nil, icon: hosted?.icon ?? NSWorkspace.shared.icon(forFile: path), tint: ProgramTint.color(for: name),
            kind: .program, label: name, detail: hosted?.localizedName.map { String(localized: "Running in \($0). Quit stops it, like Ctrl-C.") })
    }

    private static func owner(of pid: pid_t) -> uid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbsi_uid
    }

    /// Where macOS keeps its own programs. `/usr/local` is yours (Homebrew on Intel, and other installers).
    static func isPartOfMacOS(_ path: String) -> Bool {
        if path.hasPrefix("/usr/local/") { return false }
        return ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/var/", "/Library/Developer/"]
            .contains { path.hasPrefix($0) }
    }

    /// `/Applications/Docker.app/Contents/MacOS/com.docker.backend` → `/Applications/Docker.app`: the outermost app.
    static func enclosingApp(of path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
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
