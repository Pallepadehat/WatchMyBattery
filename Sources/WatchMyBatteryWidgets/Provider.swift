import AppKit
import BatteryKit
import WidgetKit

/// One moment of a widget: the battery then, and what the app last said about the rest.
struct BatteryEntry: TimelineEntry {
    let date: Date
    /// The battery at `date`: read from macOS for now, and from the forecast for the entries after.
    let battery: WidgetState.Battery?
    /// What the app wrote last; `nil` if it never has (it isn't running, or was built without the app group).
    let state: WidgetState?

    /// An app's icon, from the PNG the app left next to the state.
    func icon(for app: WidgetState.App) -> NSImage? {
        guard let file = app.iconFile, let folder = SharedState.folder else { return nil }
        return NSImage(contentsOf: folder.appending(path: file))
    }

    static let preview = BatteryEntry(
        date: Date(),
        battery: .init(percentage: 72, isPluggedIn: false, isCharging: false, isLowPowerModeOn: false, timeRemaining: 4 * 3600 + 35 * 60, chargeTarget: 100),
        state: WidgetState(
            battery: nil,
            apps: [
                .init(
                    key: "com.apple.dt.Xcode", name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", share: 0.42, batteryTime: 52 * 60, iconFile: nil,
                    tint: [0.25, 0.55, 0.95]),
                .init(
                    key: "com.apple.Safari", name: "Safari", bundleIdentifier: "com.apple.Safari", share: 0.23, batteryTime: 28 * 60, iconFile: nil,
                    tint: [0.2, 0.6, 1.0]),
                .init(
                    key: "com.figma.Desktop", name: "Figma", bundleIdentifier: "com.figma.Desktop", share: 0.12, batteryTime: 15 * 60, iconFile: nil,
                    tint: [0.65, 0.4, 0.95]),
            ],
            accessories: [
                .init(
                    id: "airpods", name: "AirPods Pro", symbol: "airpodspro",
                    parts: [.init(role: "both", percentage: 64, isCharging: false), .init(role: "case", percentage: 90, isCharging: true)]),
                .init(id: "mouse", name: "Magic Mouse", symbol: "magicmouse.fill", parts: [.init(role: "single", percentage: 18, isCharging: false)]),
                .init(id: "keyboard", name: "Magic Keyboard", symbol: "keyboard.fill", parts: [.init(role: "single", percentage: 81, isCharging: false)]),
            ],
            forecast: WidgetState.Forecast(
                points: (0...24).map {
                    WidgetState.Forecast.Point(date: Date().addingTimeInterval(Double($0) * 900), percentage: max(72 - Double($0) * 2.6, 0))
                },
                reachesLow: Date().addingTimeInterval(5 * 3600), runsOut: nil, lowLevel: 20),
            levels: (0..<48).map { index in
                let start = Date().addingTimeInterval(Double(index - 48) * 1800)
                let level = index < 14 ? 40 + index * 4 : index < 20 ? 96 : 96 - (index - 20) * 1
                return WidgetState.Level(start: start, percentage: min(level, 100), isPluggedIn: index < 20)
            },
            usedToday: 38, batteryTimeToday: 3 * 3600 + 20 * 60))
}

/// The app group's container, where the app leaves ``WidgetState``.
enum SharedState {
    static var folder: URL? {
        // Only with the signing team's prefix: an ad hoc build has none, and no container to share.
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WMBAppGroup") as? String,
            group.wholeMatch(of: /[A-Z0-9]{10}\..+/) != nil
        else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func read() -> WidgetState? {
        guard let url = folder?.appending(path: WidgetState.fileName), let data = try? Data(contentsOf: url) else { return nil }
        return WidgetState.decode(data)
    }
}

struct BatteryProvider: TimelineProvider {
    /// How long a timeline lasts before WidgetKit asks again. The app asks sooner whenever something changes.
    static let timelineLength: TimeInterval = 30 * 60
    /// The steps the forecast fills in between.
    static let step: TimeInterval = 5 * 60
    /// The app's state older than this, and it's asked for fresh state (it may not be running, which is fine).
    static let staleAfter: TimeInterval = 20 * 60

    func placeholder(in context: Context) -> BatteryEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(context.isPreview ? .preview : entries(now: Date()).first ?? .preview)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: entries(now: now), policy: .after(now.addingTimeInterval(Self.timelineLength))))
    }

    /// Now, from macOS, then on battery a step every five minutes along the forecast, so the widget keeps counting
    /// down between the app's updates.
    private func entries(now: Date) -> [BatteryEntry] {
        let state = SharedState.read()
        if state.map({ now.timeIntervalSince($0.updatedAt) > Self.staleAfter }) ?? true { WidgetCommand.refresh.post() }
        let snapshot = PowerSourceReader.read()
        var live = snapshot.hasBattery ? WidgetState.Battery(snapshot) : state?.battery
        // macOS's reading doesn't know WatchMyBattery's charge limit; the app's state does.
        if let known = state?.battery, known.isPluggedIn, live?.isPluggedIn == true, let target = live?.chargeTarget {
            live?.chargeTarget = min(target, known.chargeTarget)
        }
        var entries = [BatteryEntry(date: now, battery: live, state: state)]
        guard let live, !live.isPluggedIn, let forecast = state?.forecast else { return entries }
        var date = now.addingTimeInterval(Self.step)
        while date < now.addingTimeInterval(Self.timelineLength) {
            guard let expected = forecast.percentage(at: date) else { break }
            var battery = live
            // Never above what macOS reads now: the forecast was made a while ago and may be a little behind.
            battery.percentage = min(live.percentage, max(Int(expected.rounded()), 0))
            battery.timeRemaining = live.timeRemaining.map { max($0 - date.timeIntervalSince(now), 0) }
            entries.append(BatteryEntry(date: date, battery: battery, state: state))
            date = date.addingTimeInterval(Self.step)
        }
        return entries
    }
}
