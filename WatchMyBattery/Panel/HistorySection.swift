import AppKit
import BatteryKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// The last 24 hours: the battery level with the time plugged in marked,
/// how long it's been on battery since it was unplugged, and the apps that
/// used the most of it.
struct HistorySection: View {
    let history: BatteryHistory
    let snapshot: BatterySnapshot
    let usesColor: Bool
    /// The panel is on screen. It's only hidden when closed, so the clock below has to know to stop.
    let isVisible: Bool
    @Binding var isExpanded: Bool

    /// A minute is plenty: nothing here changes faster.
    @State private var now = Date()

    private var start: Date { now.addingTimeInterval(-BatteryHistory.retention) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureRow(title: "Last 24 Hours", isExpanded: $isExpanded)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    LevelChart(
                        buckets: history.levelBuckets(endingAt: now, current: snapshot), start: start, now: now, current: snapshot,
                        usesColor: usesColor)

                    if let stretch = history.sinceUnplugged(snapshot, now: now) {
                        SinceUnpluggedRow(stretch: stretch)
                    }

                    AppHistoryList(apps: history.appEnergy(since: start), sampledTime: history.sampledTime(since: start))
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .task(id: isExpanded && isVisible) {
            guard isExpanded, isVisible else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
            }
        }
    }
}

/// "Last 24 Hours ›": opens and closes the history, like a disclosure group in a menu.
private struct DisclosureRow: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? Text("Shown") : Text("Hidden"))
        .accessibilityHint("Shows the battery level and the apps that used the most battery over the last 24 hours.")
    }
}

// MARK: - The level chart

/// The battery level over the last 24 hours as a bar every half hour, like
/// iPhone's Battery settings: green while plugged in, red when it ran low.
/// Before history begins there are no bars, so a new history reads as new
/// rather than as one thin line stretched across the day.
private struct LevelChart: View {
    let buckets: [BatteryHistory.LevelBucket]
    let start: Date
    let now: Date
    let current: BatterySnapshot
    let usesColor: Bool

    @Environment(\.colorScheme) private var colorScheme

    private static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
    private static let red = Color(red: 0.95, green: 0.27, blue: 0.23)
    /// Room between bars, as a share of each slot.
    private static let gap = 0.28

    private var filled: [BatteryHistory.LevelBucket] { buckets.filter { $0.percentage != nil } }

    var body: some View {
        Chart(filled) { bucket in
            bar(bucket)
        }
        .chartXScale(domain: start...now)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2])).foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour(), collisionResolution: .greedy)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let level = value.as(Int.self) {
                        Text(Double(level) / 100, format: .percent)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .overlay {
            if filled.isEmpty {
                Text("The battery level shows here as it changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        // About iPhone's proportions across the panel's width, so the bars read at a glance.
        .frame(height: 128)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level, last 24 hours")
        .accessibilityValue(accessibilitySummary)
    }

    /// One half hour: a bar from empty up to the level, a little narrower than its slot.
    private func bar(_ bucket: BatteryHistory.LevelBucket) -> some ChartContent {
        let inset: TimeInterval = bucket.end.timeIntervalSince(bucket.start) * Self.gap / 2
        let from: Date = bucket.start.addingTimeInterval(inset)
        let to: Date = bucket.end.addingTimeInterval(-inset)
        let level: Int = bucket.percentage ?? 0
        return RectangleMark(xStart: .value("Start", from), xEnd: .value("End", to), yStart: .value("Empty", 0), yEnd: .value("Level", level))
            .cornerRadius(1.5)
            .foregroundStyle(color(for: bucket))
    }

    private func color(for bucket: BatteryHistory.LevelBucket) -> Color {
        let plain = colorScheme == .dark ? Color.white.opacity(0.85) : Color(white: 0.12).opacity(0.85)
        guard usesColor else { return bucket.isPluggedIn ? plain.opacity(0.45) : plain }
        if bucket.isPluggedIn { return Self.green }
        if let level = bucket.percentage, level <= BatteryIcon.lowPercentage { return Self.red }
        return plain
    }

    private var accessibilitySummary: String {
        let levels = filled.compactMap(\.percentage)
        guard let lowest = levels.min(), let highest = levels.max() else { return "" }
        let format = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        return String(
            localized:
                "Between \((Double(lowest) / 100).formatted(format)) and \((Double(highest) / 100).formatted(format)), now \(current.level.formatted(format))."
        )
    }
}

// MARK: - Since unplugged

/// "On battery  2:14 · 8% an hour": time since it was last unplugged, and the average drain.
private struct SinceUnpluggedRow: View {
    let stretch: BatteryHistory.BatteryStretch

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("On battery")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(details)
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .help(Text("Since \(stretch.since.formatted(date: .omitted, time: .shortened)), when the Mac was unplugged. The average includes time asleep."))
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [TimeFormat.clock(stretch.duration)]
        if let perHour = stretch.perHour {
            // Whole percents: the battery only reports whole percents, so anything finer would be made up.
            let rate = (max(perHour, 1) / 100).formatted(.percent.precision(.fractionLength(0)))
            parts.append(String(localized: "\(rate) an hour"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Apps

/// The apps that used the most battery, with a bar for their share and the battery time it cost.
private struct AppHistoryList: View {
    let apps: [BatteryHistory.AppEnergy]
    /// How much time on battery was measured; with little of it, there's not much to say yet.
    let sampledTime: TimeInterval

    private static let count = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Used the most battery")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if apps.isEmpty {
                Text(
                    sampledTime > 0
                        ? "No app has used much battery."
                        : "Apps are measured every few minutes while on battery, and show up here."
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                let shown = Array(apps.prefix(Self.count))
                let most = shown.first?.joules ?? 1
                ForEach(shown) { app in
                    AppHistoryRow(app: app, fraction: most > 0 ? app.joules / most : 0)
                }
            }
        }
    }
}

private struct AppHistoryRow: View {
    let app: BatteryHistory.AppEnergy
    /// Its energy compared with the hungriest app's, 0–1.
    let fraction: Double

    var body: some View {
        let look = AppLook.of(app.app)
        HStack(spacing: 7) {
            Image(nsImage: look.icon)
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.app.name)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let cost {
                        Text(cost)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))
                GeometryReader { proxy in
                    Capsule()
                        .fill(look.tint)
                        .frame(width: max(proxy.size.width * fraction, 3))
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.app.name)
        .accessibilityValue(cost.map { Text("Cost \($0) of battery") } ?? Text(verbatim: ""))
    }

    /// Under a minute rounds away to nothing, so it says so instead.
    private var cost: String? {
        guard let time = app.batteryTime else { return nil }
        return time < 60 ? String(localized: "under 1m") : TimeFormat.compact(time)
    }
}

/// Icons and colours of apps in the history, which may not be running any more.
private enum AppLook {
    struct Look {
        let icon: NSImage
        let tint: Color
    }

    @MainActor private static var cache: [String: Look] = [:]

    @MainActor static func of(_ app: BatteryHistory.AppIdentity) -> Look {
        if let look = cache[app.key] { return look }
        let icon: NSImage
        if let bundleIdentifier = app.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let look = Look(icon: icon, tint: IconTint.color(of: icon))
        cache[app.key] = look
        return look
    }
}
