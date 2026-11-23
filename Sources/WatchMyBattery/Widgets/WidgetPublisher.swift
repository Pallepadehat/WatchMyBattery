import AppKit
import BatteryKit
import OSLog
import SwiftUI
import WidgetKit

/// Hands the widgets and Control Center's controls what they show (``WidgetState``), in the app group's container,
/// and does what they ask (``WidgetCommand``): they're sandboxed, and can't switch Low Power Mode themselves.
///
/// It follows what's already observed (the battery snapshot, the accessories, the history), waits a couple of seconds
/// for changes to settle, and only writes, and asks WidgetKit to redraw, when something the widgets show changed. So it
/// adds no reading of its own, and WidgetKit's reload budget goes on changes you'd see.
final class WidgetPublisher {
    private weak var model: AppModel?
    private var pending: Task<Void, Never>?
    private var last: WidgetState?
    private var lastWritten = Date.distantPast
    /// Icons already in the container, by file name.
    private var writtenIcons: Set<String> = []
    private let folder: URL?

    /// Changes this close together are written once.
    private static let settleTime: Duration = .seconds(2)
    /// Written at least this often while anything changes, so the time left doesn't go stale.
    private static let refreshInterval: TimeInterval = 15 * 60

    /// The app group shared with the widget extension, from the Info.plist, which has the signing team's prefix
    /// (`ABCDE12345.com.pallepadehat.WatchMyBattery`). `nil` in a build without a team, which has no widgets.
    static var appGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WMBAppGroup") as? String,
            group.wholeMatch(of: /[A-Z0-9]{10}\..+/) != nil
        else { return nil }
        return group
    }

    init() {
        // An isolated run, or a made-up battery, mustn't show in the real widgets.
        if LaunchOptions.isIsolated || LaunchOptions.pretendsCharging {
            folder = nil
        } else {
            folder = Self.appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        }
    }

    func start(model: AppModel) {
        self.model = model
        guard let folder else {
            Logger.app.notice("No app group container: the widgets won't get the app's state")
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        writtenIcons = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("icon-") && $0.hasSuffix(".png") }
        listenForCommands()
        observe()
    }

    // MARK: - Watching

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.battery.snapshot
            _ = model.accessories.accessories
            _ = model.history.revision
            _ = model.history.history.levels.last
            _ = model.lowPowerMode.isSupported
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleWrite()
                self?.observe()
            }
        }
        scheduleWrite()
    }

    private func scheduleWrite(force: Bool = false) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleTime)
            guard !Task.isCancelled else { return }
            self?.write(force: force)
        }
    }

    /// Writes the state when it changed visibly, or has gone stale, or a widget asked (`force`). WidgetKit is only
    /// asked to redraw for a visible change: its reload budget is limited, and a fresher time stamp alone shows nothing.
    private func write(force: Bool) {
        guard let model, let folder else { return }
        let state = makeState(model)
        let isVisible = state.differsVisibly(from: last)
        let isStale = Date().timeIntervalSince(lastWritten) >= Self.refreshInterval
        guard force || isStale || isVisible else { return }
        do {
            try state.encoded().write(to: folder.appending(path: WidgetState.fileName), options: .atomic)
            last = state
            lastWritten = Date()
        } catch {
            Logger.app.error("Couldn't write the widgets' state: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard isVisible else { return }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    private func makeState(_ model: AppModel) -> WidgetState {
        let snapshot = model.battery.snapshot
        let now = Date()
        let history = model.history.history
        let since = now.addingTimeInterval(-BatteryHistory.retention)
        let energy = history.appEnergy(since: since).filter { !model.settings.isExcluded(bundleIdentifier: $0.app.bundleIdentifier) }
        let total = energy.reduce(0) { $0 + $1.joules }
        let apps = energy.prefix(4).map { app in
            let look = AppLook.of(app.app)
            return WidgetState.App(
                key: app.id, name: app.app.name, bundleIdentifier: app.app.bundleIdentifier, share: total > 0 ? app.joules / total : 0,
                batteryTime: app.batteryTime, iconFile: icon(for: look, key: app.id), tint: Self.components(of: look.tint))
        }
        let accessories = model.accessories.accessories.map { accessory in
            WidgetState.Accessory(
                id: accessory.id, name: accessory.name, symbol: accessory.symbols.device,
                parts: accessory.displayParts.map { .init(role: Self.roleName($0.role), percentage: $0.percentage, isCharging: $0.isCharging) })
        }
        let forecast = model.forecast.map(WidgetState.Forecast.init)
        let levels = history.levelBuckets(endingAt: now, current: snapshot).compactMap { bucket in
            bucket.percentage.map { WidgetState.Level(start: bucket.start, percentage: $0, isPluggedIn: bucket.isPluggedIn) }
        }
        let today = model.history.profile.days(1, endingAt: now).first
        return WidgetState(
            updatedAt: now, battery: snapshot.hasBattery ? .init(snapshot) : nil, apps: apps, accessories: accessories, forecast: forecast,
            levels: levels, usedToday: today?.drained, batteryTimeToday: today?.batterySeconds, canSwitchLowPowerMode: model.lowPowerMode.isSupported)
    }

    private static func roleName(_ role: Accessory.Part.Role) -> String {
        switch role {
        case .left: "left"
        case .right: "right"
        case .both: "both"
        case .single: "single"
        case .case: "case"
        }
    }

    /// The app's icon as a small PNG in the container, written once, for the widgets, which can't look it up. The
    /// panel's own (``AppLook``): an app's icon, System Settings' for macOS's work, a terminal's for a command.
    private func icon(for look: AppLook.Look, key: String) -> String? {
        guard let folder else { return nil }
        // Keys can be names ("name:Window Server"): keep the file name plain.
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        let name = "icon-" + String(safe) + ".png"
        if writtenIcons.contains(name) { return name }
        let size = NSSize(width: 64, height: 64)
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        look.icon.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        do {
            try png.write(to: folder.appending(path: name), options: .atomic)
            writtenIcons.insert(name)
            return name
        } catch {
            return nil
        }
    }

    private static func components(of color: Color) -> [Double]? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map(Double.init)
    }

    // MARK: - Commands from the widgets

    private func listenForCommands() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for command in WidgetCommand.allCases {
            CFNotificationCenterAddObserver(
                center, observer,
                { _, observer, name, _, _ in
                    guard let observer, let raw = name?.rawValue as String?, let command = WidgetCommand(rawValue: raw) else { return }
                    let publisher = Unmanaged<WidgetPublisher>.fromOpaque(observer).takeUnretainedValue()
                    // Delivered on the main thread, whose run loop it was added on.
                    MainActor.assumeIsolated { publisher.handle(command) }
                }, command.rawValue as CFString, nil, .deliverImmediately)
        }
    }

    private func handle(_ command: WidgetCommand) {
        guard let model else { return }
        Logger.app.notice("A widget asked: \(command.rawValue, privacy: .public)")
        switch command {
        case .lowPowerModeOn: model.setLowPowerMode(true)
        case .lowPowerModeOff: model.setLowPowerMode(false)
        case .refresh: scheduleWrite(force: true)
        }
    }
}
