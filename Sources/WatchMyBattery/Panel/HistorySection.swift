import AppKit
import BatteryKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// The battery's history. Over the last 24 hours: the level with the time
/// plugged in marked, how long it's been on battery since it was unplugged,
/// and the apps that used the most of it. Over the last 10 days, like
/// iPhone's: how much battery each day used, an average day, and the apps;
/// click a day for its own. Click an app for a closer look, and Settings ›
/// History has the rest.
struct HistorySection: View {
    /// The recorder rather than its history, so the history is only read (and the panel only redrawn when it
    /// changes) while the section is open.
    let recorder: HistoryRecorder
    let snapshot: BatterySnapshot
    let usesColor: Bool
    /// The panel is on screen. It's only hidden when closed, so the clock below has to know to stop.
    let isVisible: Bool
    @Binding var isExpanded: Bool
    @Binding var range: HistoryRange
    /// The level chart goes on past now, to where the battery is headed.
    var showsForecast = true
    /// Opens Settings › History, at an app's own history when its key is given.
    let openHistory: (String?) -> Void

    /// A minute is plenty: nothing here changes faster.
    @State private var now = Date()
    /// A day picked in the ten-day chart, by its start: its numbers and apps instead of the ten days'.
    @State private var selectedDay: Date? = Self.previewState.day
    /// The app whose row is open, by its key.
    @State private var openApp: String? = Self.previewState.app

    /// What the section opens with: nothing picked, except in the preview renderer's pictures of it.
    @MainActor static var previewState: (day: Date?, app: String?) = (nil, nil)
    @State private var showsMoreApps = false

    private var start: Date { now.addingTimeInterval(-BatteryHistory.retention) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureRow(title: range == .day ? "Last 24 Hours" : "Last 10 Days", isExpanded: $isExpanded)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Period", selection: $range.animation(.snappy(duration: 0.25))) {
                        ForEach(HistoryRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)

                    switch range {
                    case .day: lastDay
                    case .tenDays: lastTenDays
                    }

                    HStack {
                        Spacer()
                        Button("All History…") { openHistory(nil) }
                            .buttonStyle(.link)
                            .font(.system(size: 11, weight: .medium))
                            .help("Every app, day by day, for as long as the history is kept, in Settings.")
                    }
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: range) {
            selectedDay = nil
            openApp = nil
        }
        .onChange(of: selectedDay) { openApp = nil }
        .task(id: isExpanded && isVisible) {
            guard isExpanded, isVisible else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
            }
        }
    }
}

extension HistorySection {
    @ViewBuilder private var lastDay: some View {
        let history = recorder.history
        let forecast =
            showsForecast
            ? ForecastModel.forecast(snapshot: snapshot, profile: recorder.profile, history: history, now: now, lowLevel: BatteryIcon.lowPercentage)
            : nil
        LevelChart(
            buckets: history.levelBuckets(endingAt: now, current: snapshot), start: start, now: now, current: snapshot,
            usesColor: usesColor, forecast: forecast)

        if let stretch = history.sinceUnplugged(snapshot, now: now) {
            SinceUnpluggedRow(stretch: stretch)
        }
        if let forecast, forecast.reachesLow != nil || forecast.runsOut != nil {
            ForecastRow(forecast: forecast)
        }

        appList(
            title: "Used the most battery", apps: history.appEnergy(since: start), sampledTime: history.sampledTime(since: start),
            from: start, to: now, granularity: .hour)
    }

    /// Only read while shown, like the day's history, so the panel doesn't redraw for it otherwise.
    @ViewBuilder private var lastTenDays: some View {
        let profile = recorder.profile
        let days = profile.days(10, endingAt: now)
        let since = days.first?.start ?? start
        DayChart(days: days, usesColor: usesColor, selection: $selectedDay)

        if let day = days.first(where: { $0.start == selectedDay }) {
            let end = min(Calendar.current.date(byAdding: .day, value: 1, to: day.start) ?? now, now)
            let report = profile.report(from: day.start, to: end, granularity: .hour)
            SelectedDayRow(day: day) { withAnimation(.snappy(duration: 0.25)) { selectedDay = nil } }
            appList(
                title: "Used the most on \(day.start.formatted(.dateTime.weekday(.wide)))",
                apps: report.apps.map { BatteryHistory.AppEnergy(app: $0.app, joules: $0.joules, batteryTime: $0.batteryTime) },
                sampledTime: report.sampledSeconds, from: day.start, to: end, granularity: .hour)
        } else {
            if let average = AverageDay(days) {
                AverageDayRow(average: average)
            }
            appList(
                title: "Used the most battery", apps: profile.appEnergy(since: since), sampledTime: profile.sampledTime(since: since),
                from: since, to: now, granularity: .day)
        }
    }

    /// The apps, each opening onto its own use over the same time.
    private func appList(
        title: LocalizedStringKey, apps: [BatteryHistory.AppEnergy], sampledTime: TimeInterval, from: Date, to: Date,
        granularity: UsageReport.Granularity
    ) -> some View {
        AppHistoryList(
            title: title, apps: apps, sampledTime: sampledTime, rate: recorder.pointsPerJoule, openApp: $openApp, showsMore: $showsMoreApps
        ) { app in
            AppHistoryPeek(
                report: recorder.profile.appReport(for: app.id, from: from, to: to, granularity: granularity), app: app.app,
                more: { openHistory(app.id) })
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
        .accessibilityHint("Shows the battery level and the apps that used the most battery.")
    }
}

// MARK: - The level chart

/// The battery level over the last 24 hours as a bar every half hour, like
/// iPhone's Battery settings: green while plugged in, red when it ran low.
/// Before history begins there are no bars, so a new history reads as new
/// rather than as one thin line stretched across the day.
private struct LevelChart: View {
    /// Only the slices with a level: before history begins there's nothing to draw.
    let filled: [BatteryHistory.LevelBucket]
    let start: Date
    let end: Date
    let now: Date
    let current: BatterySnapshot
    let usesColor: Bool
    /// Where the level is headed, up to the chart's end.
    let forecast: [BatteryForecast.Point]

    @Environment(\.colorScheme) private var colorScheme

    private static let red = Color(red: 0.95, green: 0.27, blue: 0.23)
    /// Room between bars, as a share of each slot.
    private static let gap = 0.28

    /// With a forecast, the chart's last quarter is the hours ahead: 18 hours back, 6 ahead.
    static let forecastSpan: TimeInterval = 6 * 3600

    init(
        buckets: [BatteryHistory.LevelBucket], start: Date, now: Date, current: BatterySnapshot, usesColor: Bool, forecast: BatteryForecast?
    ) {
        let shift = forecast == nil ? 0 : Self.forecastSpan
        let start = start.addingTimeInterval(shift)
        let end = now.addingTimeInterval(shift)
        filled = buckets.filter { $0.percentage != nil && $0.start >= start }
        self.start = start
        self.end = end
        self.now = now
        self.current = current
        self.usesColor = usesColor
        self.forecast = forecast.map { Self.clip($0.points, to: end) } ?? []
    }

    /// The points up to `end`, with one at `end` itself between the two either side, so the line stops at the edge.
    private static func clip(_ points: [BatteryForecast.Point], to end: Date) -> [BatteryForecast.Point] {
        guard let after = points.firstIndex(where: { $0.date > end }) else { return points }
        guard after > 0 else { return [] }
        let a = points[after - 1]
        let b = points[after]
        let share = end.timeIntervalSince(a.date) / b.date.timeIntervalSince(a.date)
        return Array(points[..<after]) + [BatteryForecast.Point(date: end, percentage: a.percentage + (b.percentage - a.percentage) * share)]
    }

    var body: some View {
        Chart {
            ForEach(filled) { bucket in
                bar(bucket)
            }
            if !forecast.isEmpty {
                forecastMarks
            }
        }
        .chartXScale(domain: start...end)
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
        .accessibilityLabel(forecast.isEmpty ? "Battery level, last 24 hours" : "Battery level, and where it's headed")
        .accessibilityValue(accessibilitySummary)
    }

    /// The hours ahead: a soft band under a dashed line from now, the way the level should go, and a hairline at now.
    @ChartContentBuilder private var forecastMarks: some ChartContent {
        RuleMark(x: .value("Now", now))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .foregroundStyle(Color.secondary.opacity(0.35))
        ForEach(forecast) { point in
            AreaMark(x: .value("Time", point.date), y: .value("Expected", point.percentage), series: .value("Series", "forecast"))
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [forecastColor.opacity(0.22), forecastColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
        }
        ForEach(forecast) { point in
            LineMark(x: .value("Time", point.date), y: .value("Expected", point.percentage), series: .value("Series", "forecast line"))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
                .foregroundStyle(forecastColor)
        }
    }

    /// The bars' grey, or red when the line ends up low.
    private var forecastColor: Color {
        guard usesColor, let last = forecast.last, last.percentage <= Double(BatteryIcon.lowPercentage) else { return .secondary }
        return Self.red
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

    /// Time on battery: a quiet grey, so the green of time plugged in, and the red of running low, stand out.
    static let plainBar = Color.secondary.opacity(0.55)

    private func color(for bucket: BatteryHistory.LevelBucket) -> Color {
        let plain = Self.plainBar
        guard usesColor else { return bucket.isPluggedIn ? plain.opacity(0.45) : plain }
        if bucket.isPluggedIn { return ChargeTrack.green }
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

// MARK: - The ten-day chart

/// How much battery each of the last ten days used, a bar a day, like iPhone's Battery settings. A day can use more
/// than 100% when the Mac was charged in between. Click a day to see its own apps.
private struct DayChart: View {
    let days: [UsageProfile.Day]
    let usesColor: Bool
    @Binding var selection: Date?

    var body: some View {
        let top = max(100, days.map(\.drained).max() ?? 0)
        Chart(days) { day in
            BarMark(x: .value("Day", day.start, unit: .day), y: .value("Used", day.drained), width: .ratio(0.62))
                .cornerRadius(1.5)
                .foregroundStyle(color(for: day))
        }
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: days.map(\.start)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 10, weight: date == selection ? .bold : .regular))
                            .foregroundStyle(date == selection ? Color.primary : Color.secondary)
                    }
                }
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
            if days.allSatisfy({ $0.drained == 0 }) {
                Text("Each day's battery use shows here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(PeriodPicking(periods: intervals, selection: $selection))
        .frame(height: 128)
        .help("Click a day to see the apps that used the most battery that day.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery used each day, last 10 days")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Adjust to pick a day and see its apps.")
    }

    private var intervals: [DateInterval] {
        days.map { day in
            DateInterval(start: day.start, end: Calendar.current.date(byAdding: .day, value: 1, to: day.start) ?? day.start.addingTimeInterval(24 * 3600))
        }
    }

    /// The picked day stands out; the others step back.
    private func color(for day: UsageProfile.Day) -> Color {
        let plain = LevelChart.plainBar
        guard let selection else { return plain }
        guard day.start == selection else { return plain.opacity(0.4) }
        return usesColor ? Color.accentColor : Color.primary.opacity(0.75)
    }

    private var accessibilitySummary: String {
        let format = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        if let day = days.first(where: { $0.start == selection }) {
            return "\(day.start.formatted(.dateTime.weekday(.wide))) \((Double(day.drained) / 100).formatted(format))"
        }
        return days.filter { $0.drained > 0 }
            .map { "\($0.start.formatted(.dateTime.weekday(.wide))) \((Double($0.drained) / 100).formatted(format))" }
            .joined(separator: ", ")
    }
}

/// "Tuesday 12 Nov  2:10 on battery · 34% used", for the day picked in the chart, with a way back to all ten.
private struct SelectedDayRow: View {
    let day: UsageProfile.Day
    let clear: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(day.start, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(details)
                .monospacedDigit()
                .lineLimit(1)
            DismissButton(title: String(localized: "the day"), action: clear)
                .help("Back to the last 10 days")
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        String(localized: "\(TimeFormat.clock(day.batterySeconds)) on battery · \(HistoryText.points(Double(day.drained))) used")
    }
}

/// An average day on battery, over the days that had any.
private struct AverageDay {
    let batteryTime: TimeInterval
    /// Percentage points.
    let used: Double

    init?(_ days: [UsageProfile.Day]) {
        let used = days.filter { $0.drained > 0 || $0.batterySeconds >= 60 }
        guard !used.isEmpty else { return nil }
        batteryTime = used.reduce(0) { $0 + $1.batterySeconds } / Double(used.count)
        self.used = Double(used.reduce(0) { $0 + $1.drained }) / Double(used.count)
    }
}

/// "Average day  2:10 on battery · 34% used".
private struct AverageDayRow: View {
    let average: AverageDay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Average day")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(details)
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .help(Text("Over the days the Mac ran on battery. Time on battery includes time asleep."))
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        let used = (average.used / 100).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(TimeFormat.clock(average.batteryTime)) on battery · \(used) used")
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

/// "Forecast · 20% around 16:40": when the battery should run low, at the pace it's going and how it usually goes later
/// in the day, as the chart's dashed line shows.
private struct ForecastRow: View {
    let forecast: BatteryForecast

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Forecast")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            // Both times when they fit on the line; otherwise the first, the one that matters sooner.
            ViewThatFits(in: .horizontal) {
                Text(details(includingEmpty: true))
                Text(details(includingEmpty: false))
            }
            .monospacedDigit()
            .lineLimit(1)
        }
        .font(.system(size: 12))
        .help(help)
        .accessibilityElement(children: .combine)
    }

    private func details(includingEmpty: Bool) -> String {
        let low = (Double(forecast.lowLevel) / 100).formatted(.percent.precision(.fractionLength(0)))
        var parts: [String] = []
        if let reachesLow = forecast.reachesLow {
            parts.append(String(localized: "\(low) around \(Self.time(reachesLow))"))
        }
        if let runsOut = forecast.runsOut, includingEmpty || parts.isEmpty {
            parts.append(String(localized: "empty around \(Self.time(runsOut))"))
        }
        return parts.joined(separator: " · ")
    }

    /// "16:40", or "Tue 08:10" when it's not today.
    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var help: Text {
        switch forecast.basis {
        case .usualDay:
            Text("At the pace your Mac is going now, then the way the battery usually goes at these hours. A guess, not a promise: it moves with what you do.")
        case .currentPace:
            Text("At the pace your Mac is going now. Once there's a few days of history, it also counts how the battery usually goes later in the day.")
        }
    }
}

// MARK: - Apps

/// The apps that used the most battery, with a bar for their share and how much of the battery each used. Three to start
/// with, more on request; click one to open a closer look under it.
private struct AppHistoryList<Peek: View>: View {
    let title: LocalizedStringKey
    let apps: [BatteryHistory.AppEnergy]
    /// How much time on battery was measured; with little of it, there's not much to say yet.
    let sampledTime: TimeInterval
    /// Percentage points of the battery per joule, to say how much of it each app used.
    let rate: Double?
    @Binding var openApp: String?
    @Binding var showsMore: Bool
    @ViewBuilder let peek: (BatteryHistory.AppEnergy) -> Peek

    private static var count: Int { 3 }
    private static var moreCount: Int { 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if apps.count > Self.count {
                    Button(showsMore ? "Show Fewer" : "Show More") {
                        withAnimation(.snappy(duration: 0.3)) { showsMore.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
                }
            }

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
                let shown = Array(apps.prefix(showsMore ? Self.moreCount : Self.count))
                let most = shown.first?.joules ?? 1
                let all = apps.reduce(0) { $0 + $1.joules }
                ForEach(shown) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.snappy(duration: 0.3)) { openApp = openApp == app.id ? nil : app.id }
                        } label: {
                            AppHistoryRow(
                                app: app, fraction: most > 0 ? app.joules / most : 0, share: all > 0 ? app.joules / all : 0, rate: rate,
                                isOpen: openApp == app.id)
                        }
                        .buttonStyle(.plain)
                        if openApp == app.id {
                            peek(app)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

private struct AppHistoryRow: View {
    let app: BatteryHistory.AppEnergy
    /// Its energy compared with the hungriest app's, 0–1.
    let fraction: Double
    /// Its share of what the apps used, 0–1, for when there's no rate yet.
    let share: Double
    let rate: Double?
    let isOpen: Bool

    @State private var isHovered = false

    var body: some View {
        let look = AppLook.of(app.app)
        HStack(spacing: 7) {
            Image(nsImage: look.icon)
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(app.app.name)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(used)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help(usedHelp)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .opacity(isOpen || isHovered ? 1 : 0)
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
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.app.name)
        .accessibilityValue(usedHelp)
        .accessibilityHint(isOpen ? Text("Hides its history.") : Text("Shows its history."))
        .accessibilityAddTraits(.isButton)
    }

    /// "6%" of the battery; until this Mac's rate is known, its share of what the apps used.
    private var used: String { HistoryText.batteryUse(joules: app.joules, rate: rate) ?? HistoryText.share(share) }

    private var usedHelp: Text {
        if let use = HistoryText.batteryUse(joules: app.joules, rate: rate) { return Text("Used about \(use) of the battery") }
        return Text("\(HistoryText.share(share)) of what the apps used")
    }
}

/// A closer look at one app, under its row: its use over the same time, a line about it, and the way to its full
/// history in Settings.
private struct AppHistoryPeek: View {
    let report: AppUsageReport?
    let app: BatteryHistory.AppIdentity
    let more: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let report {
                AppSparkline(report: report, tint: AppLook.of(app).tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let report {
                    Text(HistoryText.peekFacts(report))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                Button(action: more) {
                    HStack(spacing: 2) {
                        Text("History")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.link)
                .fontWeight(.medium)
                .help("\(app.name)'s battery use, day by day, in Settings.")
            }
            .font(.system(size: 11))
        }
        .padding(.leading, 25)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }
}

/// An app's use as a small bar chart with no axes: only the shape matters here, and its two ends are named below
/// it ("24h ago … now", "Mon … Today").
private struct AppSparkline: View {
    let report: AppUsageReport
    let tint: Color

    var body: some View {
        let values = report.periods.map { $0.batteryTime ?? $0.joules }
        let top = max(values.max() ?? 0, .leastNonzeroMagnitude)
        VStack(spacing: 3) {
            Chart {
                RuleMark(y: .value("None", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.quaternary)
                ForEach(Array(report.periods.enumerated()), id: \.element.id) { index, period in
                    if values[index] > 0 {
                        let half = report.granularity == .hour ? 0.33 : 0.27
                        RectangleMark(
                            xStart: .value("From", Double(index) - half), xEnd: .value("To", Double(index) + half),
                            yStart: .value("None", 0), yEnd: .value("Used", max(values[index] / top, 0.06))
                        )
                        .cornerRadius(1.5)
                        .foregroundStyle(tint.gradient)
                    }
                }
            }
            .chartXScale(domain: -0.5...Double(max(report.periods.count, 1)) - 0.5)
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 30)

            HStack {
                Text(leadingLabel)
                Spacer()
                Text(trailingLabel)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(report.app.name), battery used over time"))
    }

    private var leadingLabel: String {
        guard let first = report.periods.first?.start else { return "" }
        switch report.granularity {
        case .hour: return isUpToNow ? String(localized: "24h ago") : first.formatted(date: .omitted, time: .shortened)
        case .day, .week: return first.formatted(.dateTime.weekday(.abbreviated))
        }
    }

    private var trailingLabel: String {
        guard let last = report.periods.last else { return "" }
        if isUpToNow { return report.granularity == .hour ? String(localized: "Now") : String(localized: "Today") }
        return last.end.formatted(date: .omitted, time: .shortened)
    }

    /// The report runs up to now, rather than being a day picked in the past.
    private var isUpToNow: Bool { (report.periods.last?.end ?? .distantPast).timeIntervalSinceNow > -5 * 60 }
}

extension String {
    /// "18% of what apps used" stays as it is; "on 6 of 10 days" → "On 6 of 10 days", at the start of a line.
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// Icons and colours of apps in the history, which may not be running any more.
enum AppLook {
    struct Look {
        let icon: NSImage
        let tint: Color
    }

    @MainActor private static var cache: [String: Look] = [:]

    @MainActor static func of(_ app: BatteryHistory.AppIdentity) -> Look {
        if let look = cache[app.key] { return look }
        let look: Look
        if let bundleIdentifier = app.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            look = Look(icon: icon, tint: IconTint.color(of: icon, for: app.key))
        } else {
            // A part of macOS, a program that isn't an app, or an app that's since gone: the same icon the panel gives it.
            if let service = MacOSServices.all.first(where: { $0.name == app.name }) {
                let icon = service.icon
                look = Look(icon: icon, tint: IconTint.color(of: icon, for: app.key))
            } else if let icon = InstalledApps.icon(forCommand: app.name) {
                look = Look(icon: icon, tint: IconTint.color(of: icon, for: app.key))
            } else {
                look = Look(icon: NSWorkspace.shared.icon(for: .unixExecutable), tint: ProgramTint.color(for: app.name))
            }
        }
        cache[app.key] = look
        return look
    }
}
