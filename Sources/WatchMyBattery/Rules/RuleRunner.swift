import AppKit
import BatteryKit
import OSLog
import Observation

/// Runs the rules in Settings › Rules: when the battery drops to a level, charges to one, or the charger is connected
/// or disconnected, it turns Low Power Mode on or off, quits apps, sets the charge limit, runs a shortcut, or says so in
/// a notification.
///
/// It only watches the battery snapshot, which changes by notification, so it costs nothing in between. ``RuleEngine``
/// decides when a rule is due.
@Observable
final class RuleRunner {
    /// When each rule last ran, by ID, for Settings to show. Kept while the app runs.
    private(set) var lastRun: [UUID: Date] = [:]
    /// What went wrong the last time each rule ran, if anything ("Couldn't find the shortcut “Focus”").
    private(set) var problems: [UUID: String] = [:]
    /// The shortcuts in the Shortcuts app, by name, once they've been asked for.
    private(set) var shortcuts: [String] = []
    private(set) var isLoadingShortcuts = false

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var engine = RuleEngine()
    @ObservationIgnored private var knownRules: [BatteryRule] = []

    nonisolated static let shortcutsTool = "/usr/bin/shortcuts"

    func start(model: AppModel) {
        self.model = model
        observe()
    }

    private func observe() {
        guard let model else { return }
        let (snapshot, rules) = withObservationTracking {
            (model.battery.snapshot, model.settings.rules)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        // A rule made or changed doesn't run just because the battery's already past its level.
        if rules != knownRules {
            let old = Dictionary(knownRules.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for rule in rules where old[rule.id] != rule { engine.didChange(rule) }
            knownRules = rules
        }
        for rule in engine.update(with: snapshot, rules: rules) { run(rule) }
    }

    /// Runs a rule's actions now: when it's due, or from Settings' Try button.
    func run(_ rule: BatteryRule) {
        guard let model else { return }
        Logger.app.notice("Running a rule: \(rule.trigger.logName, privacy: .public)")
        lastRun[rule.id] = Date()
        problems[rule.id] = nil
        var done: [String] = []
        for action in rule.actions {
            switch action {
            case .lowPowerMode(let on):
                guard model.lowPowerMode.isSupported, model.battery.snapshot.isLowPowerModeOn != on else { continue }
                model.setLowPowerMode(on)
                done.append(on ? String(localized: "Turned on Low Power Mode.") : String(localized: "Turned off Low Power Mode."))
            case .quitApps(let bundleIdentifiers):
                let quit = quitApps(bundleIdentifiers)
                if !quit.isEmpty { done.append(String(localized: "Quit \(quit.formatted(.list(type: .and))).")) }
            case .chargeLimit(let level):
                guard model.chargeLimit.isSupported else { continue }
                let choice = model.chargeLimit.choices.min { abs($0 - level) < abs($1 - level) } ?? level
                guard choice != model.chargeLimit.limit else { continue }
                model.chargeLimit.set(choice)
                done.append(
                    choice >= 100
                        ? String(localized: "Turned off the charge limit.")
                        : String(localized: "Set the charge limit to \(RuleText.percent(choice))."))
            case .runShortcut(let name):
                runShortcut(name, for: rule.id)
                done.append(String(localized: "Ran the shortcut “\(name)”."))
            case .notify:
                break
            }
        }
        if rule.actions.contains(.notify) {
            let rule = rule
            Task { await model.notifier.notifyRuleRan(rule, did: done) }
        }
    }

    /// Asks each running app to quit, as quitting it from the Dock would; returns the names of the ones asked.
    private func quitApps(_ bundleIdentifiers: [String]) -> [String] {
        var names: [String] = []
        for bundleIdentifier in bundleIdentifiers {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { !$0.isTerminated }
            guard let first = running.first else { continue }
            running.forEach { $0.terminate() }
            names.append(first.localizedName ?? bundleIdentifier)
        }
        return names
    }

    // MARK: - Shortcuts

    /// Runs a shortcut with macOS's `shortcuts` tool, off the main thread, noting it if it fails.
    private func runShortcut(_ name: String, for id: UUID) {
        Task { [weak self] in
            let result = await Self.runTool(["run", name])
            guard result.status != 0 else { return }
            Logger.app.error("The shortcut \(name, privacy: .private) failed: \(result.output, privacy: .public)")
            self?.problems[id] = String(localized: "The shortcut “\(name)” didn't run. Check it's in the Shortcuts app with this name.")
        }
    }

    /// Reads the names of the shortcuts in the Shortcuts app, for the picker in Settings.
    func loadShortcuts() {
        guard !isLoadingShortcuts else { return }
        isLoadingShortcuts = true
        Task { [weak self] in
            let result = await Self.runTool(["list"])
            guard let self else { return }
            isLoadingShortcuts = false
            guard result.status == 0 else { return }
            let names = result.output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            shortcuts = Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    /// Runs `shortcuts` with these arguments and waits for it, without blocking the main thread.
    nonisolated private static func runTool(_ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            // Read to the end before waiting, on a queue of its own: a full pipe would otherwise keep the tool from exiting.
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shortcutsTool)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

extension BatteryRule.Trigger {
    /// For the log, which isn't translated.
    var logName: String {
        switch self {
        case .dropsTo(let level): "drops to \(level)%"
        case .chargesTo(let level): "charges to \(level)%"
        case .pluggedIn: "plugged in"
        case .unplugged: "unplugged"
        }
    }
}
