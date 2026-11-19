import BatteryKit
import Charts
import SwiftUI

/// Settings › History: everything the history has kept, for as long as it's kept. How much battery each day (or
/// week) used, every app that used it, and, for each app, its days, its hours and how it compares with before. Then
/// keeping, exporting and clearing the history.
///
/// Laid out like Screen Time: a few numbers, a chart under them, and the apps. Each report is worked out once, when
/// the period or the history changes, never while drawing.
struct HistoryPane: View {
    let model: AppModel
    /// The app whose page is open, by key. A page of its own within the pane, with a way back, the way System
    /// Settings opens a row.
    @State private var openApp: String?

    var body: some View {
        ZStack {
            if let key = openApp {
                AppHistoryPage(model: model, key: key) { show(nil) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                HistoryOverview(model: model) { show($0) }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear(perform: takeRequestedApp)
        .onChange(of: model.historyApp) { takeRequestedApp() }
    }

    private func show(_ key: String?) {
        withAnimation(.smooth(duration: 0.35)) { openApp = key }
    }

    /// The panel asked for an app's history: open it, once.
    private func takeRequestedApp() {
        guard let key = model.historyApp else { return }
        model.historyApp = nil
        openApp = key
    }
}

// MARK: - The overview

private struct HistoryOverview: View {
    let model: AppModel
    let open: (String) -> Void

    @State private var report: UsageReport?
    /// A bar picked in the chart, by its start: the numbers and apps are that day's (or week's) then.
    @State private var selection: Date?
    /// The picked bar's own report, worked out when it's picked rather than every time the pane draws.
    @State private var picked: UsageReport?
    @State private var showsAllApps = false
    @State private var now = Date()

    private static let appCount = 10

    var body: some View {
        let settings = model.settings
        let period = settings.historyPeriod.limited(to: settings.historyRetention)
        Form {
            if settings.recordsHistory {
                Section {
                    if let report {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .bottom) {
                                MetricRow(metrics: metrics(report))
                                Spacer(minLength: 8)
                                if selection != nil {
                                    Button("Show All") { withAnimation(.snappy(duration: 0.25)) { selection = nil } }
                                        .controlSize(.small)
                                }
                            }
                            BatteryUseChart(report: report, selection: $selection)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 190)
                    }
                } header: {
                    HStack {
                        Text("Battery Use")
                        Spacer()
                        PeriodPicker(model: model)
                    }
                }

                if let report { appsSection(report) }
            }

            Section {
                HistoryRows(model: model)
                HistoryKeepRows(model: model)
            } header: {
                Text("Keeping History")
            }
        }
        .task(id: ReportKey(period: period, revision: model.history.revision, day: Calendar.current.startOfDay(for: now))) {
            report = model.history.profile.report(from: period.start(endingAt: now), to: now, granularity: period.granularity)
            if let selection, !(report?.periods.contains { $0.start == selection } ?? false) { self.selection = nil }
            updatePicked()
        }
        .task {
            // The day changes under an open window now and then; a minute's lag is fine.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
                now = Date()
            }
        }
        .onChange(of: selection) {
            updatePicked()
            showsAllApps = false
        }
        .onChange(of: period) {
            selection = nil
            showsAllApps = false
        }
    }

    private struct ReportKey: Equatable {
        let period: HistoryPeriod
        let revision: Int
        let day: Date
    }

    private func updatePicked() {
        guard let period = pickedPeriod else {
            picked = nil
            return
        }
        picked = model.history.profile.report(from: period.start, to: period.end, granularity: .hour)
    }

    private var pickedPeriod: UsageReport.Period? { report?.periods.first { $0.start == selection } }

    /// The period's numbers, or the picked day's.
    private func metrics(_ report: UsageReport) -> [MetricItem] {
        if let period = pickedPeriod {
            return [
                MetricItem(title: Text(periodName(period, in: report)), value: HistoryText.duration(period.batterySeconds), unit: Text("on battery")),
                MetricItem(title: Text("Battery Used"), value: HistoryText.points(Double(period.drained))),
            ]
        }
        return [
            MetricItem(
                title: Text("Daily Average"), value: report.averageDay.map { HistoryText.duration($0.batterySeconds) } ?? "–",
                unit: Text("on battery")),
            MetricItem(title: Text("Used a Day"), value: report.averageDay.map { HistoryText.points($0.drained) } ?? "–"),
            MetricItem(title: Text("Total"), value: HistoryText.duration(report.batterySeconds), unit: charges(report)),
        ]
    }

    /// "9.1 charges": a total over 100% reads better as charges.
    private func charges(_ report: UsageReport) -> Text? {
        let charges = Double(report.drained) / 100
        guard charges >= 1 else { return nil }
        return Text("· \(charges.formatted(.number.precision(.fractionLength(charges < 10 ? 1 : 0)))) charges")
    }

    private func periodName(_ period: UsageReport.Period, in report: UsageReport) -> String {
        report.granularity == .week
            ? String(localized: "Week of \(period.start.formatted(.dateTime.day().month(.abbreviated)))")
            : period.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    @ViewBuilder private func appsSection(_ report: UsageReport) -> some View {
        let shownReport = picked ?? report
        let apps = shownReport.apps
        Section {
            if apps.isEmpty {
                Text(shownReport.sampledSeconds > 0 ? "No app used much battery." : "Apps show up here once they've been measured on battery.")
                    .foregroundStyle(.secondary)
            } else {
                let shown = showsAllApps ? apps : Array(apps.prefix(Self.appCount))
                let most = apps.first?.joules ?? 1
                ForEach(shown) { app in
                    AppRankRow(app: app, fraction: most > 0 ? app.joules / most : 0) { open(app.id) }
                }
                if apps.count > Self.appCount {
                    Button(showsAllApps ? String(localized: "Show Fewer") : String(localized: "Show All \(apps.count) Apps")) {
                        withAnimation(.snappy) { showsAllApps.toggle() }
                    }
                    .buttonStyle(.link)
                }
            }
        } header: {
            if let period = pickedPeriod {
                Text("Apps · \(periodName(period, in: report))")
            } else {
                Text("Apps")
            }
        } footer: {
            Text("Measured every few minutes on battery. Time is what each app's energy is worth at this Mac's average draw.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// 7D, 14D, … as far back as the history is kept.
private struct PeriodPicker: View {
    let model: AppModel

    var body: some View {
        let available = HistoryPeriod.available(keeping: model.settings.historyRetention)
        Picker(
            "Period",
            selection: Binding(
                get: { model.settings.historyPeriod.limited(to: model.settings.historyRetention) },
                set: { period in withAnimation(.snappy(duration: 0.25)) { model.settings.historyPeriod = period } })
        ) {
            ForEach(available) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }
}

// MARK: - Numbers

/// One figure in a ``MetricRow``.
struct MetricItem {
    let title: Text
    let value: String
    var unit: Text?
    var symbol: String?
    var color: Color = .primary
    var help: Text?
    /// How much it changed from before, beside its name: "↑0.8°".
    var change: Text?
}

/// A row of figures like Screen Time's: small grey names over large numbers, split by hairlines. No boxes.
///
/// Each figure keeps its size, so when the row is wider than the pane (a narrow window, or the sidebar dragged wider)
/// it goes onto two lines rather than running off the edge.
struct MetricRow: View {
    let metrics: [MetricItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(metrics.indices, spacing: 18)
            row(metrics.indices, spacing: 12)
            let half = (metrics.count + 1) / 2
            VStack(alignment: .leading, spacing: 12) {
                row(0..<half, spacing: 18)
                row(half..<metrics.count, spacing: 18)
            }
        }
    }

    private func row(_ indices: Range<Int>, spacing: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(indices, id: \.self) { index in
                if index > indices.lowerBound {
                    Divider()
                        .frame(height: 30)
                        .padding(.horizontal, spacing)
                }
                metric(metrics[index])
            }
        }
    }

    private func metric(_ item: MetricItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                item.title
                    .foregroundStyle(.secondary)
                if let change = item.change {
                    change
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }
            .font(.caption)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(item.color)
                }
                Text(item.value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit = item.unit {
                    unit
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .help(item.help ?? Text(verbatim: ""))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The battery chart

/// How much battery each day (or week) used, with the average marked. Click a bar for its apps.
private struct BatteryUseChart: View {
    let report: UsageReport
    @Binding var selection: Date?

    var body: some View {
        let periods = report.periods
        Chart {
            ForEach(periods) { period in
                BarMark(x: .value("Time", period.start, unit: unit), y: .value("Used", period.drained), width: .ratio(barWidth))
                    .cornerRadius(3)
                    .foregroundStyle(color(for: period))
            }
            // Always there, faded while a bar is picked: taking it (and its label) away would resize the plot and
            // shift every bar sideways.
            if let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(selection == nil ? 1 : 0.35))
            }
        }
        .chartYScale(domain: 0...scale.top)
        .chartXAxis {
            AxisMarks(values: HistoryAxis.dates(periods.map(\.start), granularity: report.granularity)) { _ in
                AxisValueLabel(
                    format: HistoryAxis.format(count: periods.count, granularity: report.granularity), centered: periods.count <= 14
                )
                .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.marks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let level = value.as(Int.self) {
                        Text(HistoryText.points(Double(level)))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            // The average's line is named where the axis is, like Screen Time's, rather than over the bars.
            if let average {
                AxisMarks(position: .leading, values: [average]) { _ in
                    AxisValueLabel {
                        Text("avg")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .overlay {
            if report.isEmpty {
                Text("Each day's battery use shows here, from the first time the Mac runs on battery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .modifier(PeriodPicking(periods: periods.map(\.interval), selection: $selection))
        .frame(height: 150)
        .help(report.granularity == .week ? "Click a week for its apps." : "Click a day for its apps.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(report.granularity == .week ? Text("Battery used each week") : Text("Battery used each day"))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Adjust to pick a day and see its apps.")
    }

    /// 0, 50 and 100% for days; for weeks, which use several charges each, a step that keeps three labels apart
    /// (0, 300, 600%), with the top on a step.
    private var scale: (top: Int, marks: [Int]) {
        let most = report.periods.map(\.drained).max() ?? 0
        guard most > 100 else { return (100, [0, 50, 100]) }
        let step = [100, 200, 250, 500, 1000, 2000].first { $0 * 2 >= most } ?? 5000
        let top = Int((Double(most) / Double(step)).rounded(.up)) * step
        return (top, Array(stride(from: 0, through: top, by: step)))
    }

    /// Over the days (or weeks) that used any.
    private var average: Double? {
        let used = report.periods.map(\.drained).filter { $0 > 0 }
        guard used.count >= 2 else { return nil }
        return Double(used.reduce(0, +)) / Double(used.count)
    }

    private var unit: Calendar.Component { report.granularity == .week ? .weekOfYear : .day }
    private var barWidth: Double { report.periods.count > 45 ? 0.72 : 0.58 }

    private func color(for period: UsageReport.Period) -> Color {
        guard let selection else { return Color.accentColor }
        return period.start == selection ? Color.accentColor : Color.accentColor.opacity(0.25)
    }

    private var accessibilityValue: String {
        guard let most = report.periods.max(by: { $0.drained < $1.drained }), most.drained > 0 else { return "" }
        let name = most.start.formatted(.dateTime.weekday(.wide).day().month())
        return String(
            localized: "\(HistoryText.points(Double(report.drained))) in all, the most \(HistoryText.points(Double(most.drained))) on \(name).")
    }
}

// MARK: - Apps

/// An app's row, like Screen Time's: its icon, its name over a bar for its share, and the battery time it cost.
private struct AppRankRow: View {
    let app: UsageReport.App
    let fraction: Double
    let open: () -> Void

    @State private var isHovered = false

    var body: some View {
        let look = AppLook.of(app.app)
        Button(action: open) {
            HStack(spacing: 10) {
                Image(nsImage: look.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(app.app.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(HistoryText.share(app.share))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(HistoryText.cost(app.batteryTime) ?? "")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                    ShareBar(fraction: fraction, tint: look.tint)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.app.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens its history.")
    }

    private var accessibilityValue: String {
        var parts = [String(localized: "\(HistoryText.share(app.share)) of what apps used")]
        if let cost = HistoryText.cost(app.batteryTime) { parts.append(String(localized: "Cost \(cost) of battery")) }
        return parts.joined(separator: ", ")
    }
}

/// A thin bar for an app's share, on a faint track so a short one still reads as part of something.
private struct ShareBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        Capsule()
            .fill(.quaternary.opacity(0.6))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * fraction, 4))
                }
            }
    }
}

// MARK: - An app's page

/// One app's history: what it cost, when it runs, and how that's changing.
private struct AppHistoryPage: View {
    let model: AppModel
    let key: String
    let back: () -> Void

    private enum ChartMode: Hashable {
        case days
        case hours
    }

    @State private var report: AppUsageReport?
    @State private var selection: Date?
    @State private var mode = ChartMode.days
    @State private var hasLoaded = false

    var body: some View {
        let period = model.settings.historyPeriod.limited(to: model.settings.historyRetention)
        Form {
            Section {
                if let report {
                    VStack(alignment: .leading, spacing: 16) {
                        AppHeader(report: report)
                        MetricRow(metrics: metrics(report, period: period))
                        Divider()
                        chartHeader(report)
                        switch mode {
                        case .days:
                            AppUsageBars(report: report, tint: AppLook.of(report.app).tint, height: 140, showsAxes: true, selection: $selection)
                                .transition(.opacity)
                        case .hours:
                            HourOfDayChart(report: report, tint: AppLook.of(report.app).tint)
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 4)
                } else if hasLoaded {
                    Text("There's no history for this app any more.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Button(action: back) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("All Apps")
                        }
                    }
                    .buttonStyle(.link)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back to every app (⌘[)")
                    Spacer()
                    PeriodPicker(model: model)
                }
            }

            if let report {
                Section {
                    if let first = report.firstSeen {
                        LabeledContent("First Measured", value: first.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let last = report.lastSeen {
                        LabeledContent("Last Measured") {
                            Text(last, format: .relative(presentation: .named))
                        }
                    }
                    if let bundleIdentifier = report.app.bundleIdentifier {
                        Toggle(isOn: hidden(bundleIdentifier)) {
                            Text("Hide from the Battery")
                            Text("It never gets a slice in the panel. Its history is still kept.")
                        }
                    }
                }
            }
        }
        .onExitCommand(perform: back)
        .task(id: ReportKey(key: key, period: period, revision: model.history.revision)) {
            let now = Date()
            report = model.history.profile.appReport(for: key, from: period.start(endingAt: now), to: now, granularity: period.granularity)
            hasLoaded = true
            if let selection, !(report?.periods.contains { $0.start == selection } ?? false) { self.selection = nil }
        }
    }

    private struct ReportKey: Equatable {
        let key: String
        let period: HistoryPeriod
        let revision: Int
    }

    private func hidden(_ bundleIdentifier: String) -> Binding<Bool> {
        Binding(
            get: { model.settings.isExcluded(bundleIdentifier: bundleIdentifier) },
            set: { hides in
                if hides {
                    model.settings.exclude(bundleIdentifier: bundleIdentifier)
                    model.usage.excludedApps = Set(model.settings.excludedApps)
                } else {
                    model.removeExclusion(bundleIdentifier)
                }
            })
    }

    private func metrics(_ report: AppUsageReport, period: HistoryPeriod) -> [MetricItem] {
        [
            MetricItem(title: Text("Battery Time"), value: HistoryText.cost(report.batteryTime) ?? "–"),
            MetricItem(title: Text("Average Draw"), value: report.averageWatts.map(HistoryText.watts) ?? "–"),
            MetricItem(title: Text("Active"), value: report.activeDays.formatted(), unit: Text("of \(report.dayCount) days")),
            trend(report, period: period),
        ]
    }

    private func trend(_ report: AppUsageReport, period: HistoryPeriod) -> MetricItem {
        guard let change = report.change else {
            return MetricItem(title: Text("Trend"), value: "–", help: Text("Not enough measured before to compare."))
        }
        let amount = abs(change).formatted(.percent.precision(.fractionLength(0)))
        let help = Text("\(HistoryText.change(change)) \(Text(period.before))")
        if change >= 0.1 { return MetricItem(title: Text("Trend"), value: amount, symbol: "arrow.up.right", color: .orange, help: help) }
        if change <= -0.1 { return MetricItem(title: Text("Trend"), value: amount, symbol: "arrow.down.right", color: .green, help: help) }
        return MetricItem(title: Text("Trend"), value: String(localized: "Steady"), help: help)
    }

    /// "Each Day | Through the Day", and what the chart says right now.
    private func chartHeader(_ report: AppUsageReport) -> some View {
        HStack(alignment: .center) {
            Picker("Chart", selection: $mode.animation(.snappy(duration: 0.25))) {
                Text(report.granularity == .week ? "Each Week" : "Each Day").tag(ChartMode.days)
                Text("Through the Day").tag(ChartMode.hours)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Spacer(minLength: 12)
            chartCaption(report)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
    }

    @ViewBuilder private func chartCaption(_ report: AppUsageReport) -> some View {
        switch mode {
        case .days:
            if let period = report.periods.first(where: { $0.start == selection }) {
                let name =
                    report.granularity == .week
                    ? String(localized: "Week of \(period.start.formatted(.dateTime.day().month(.abbreviated)))")
                    : period.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
                Text("\(Text(name).foregroundStyle(.primary))  \(periodCost(period))")
            } else {
                Text("Battery time it cost")
            }
        case .hours:
            if let hour = report.busiestHour {
                Text("Busiest around \(HistoryText.hourOfDay(hour))")
            } else if report.hoursOfDay.contains(where: { $0.watts != nil }) {
                Text("No hour stands out")
            } else {
                Text("Not measured at enough times of day yet")
            }
        }
    }

    private func periodCost(_ period: AppUsageReport.Period) -> String {
        if period.joules <= 0 { return String(localized: "not used") }
        if let cost = HistoryText.cost(period.batteryTime) { return cost }
        return (period.joules / 3600).formatted(.number.precision(.significantDigits(2))) + " Wh"
    }
}

/// The app's icon and name, and its place among the others.
private struct AppHeader: View {
    let report: AppUsageReport

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppLook.of(report.app).icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(report.app.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(standing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var standing: String {
        guard let rank = report.rank else { return String(localized: "Not measured using the battery in this time") }
        return String(localized: "\(HistoryText.share(report.share)) of what apps used · #\(rank) of \(report.appCount)")
    }
}

/// The app's power draw at each hour of the day, averaged over every day it was measured: when it's busy.
private struct HourOfDayChart: View {
    let report: AppUsageReport
    let tint: Color

    var body: some View {
        let measured = report.hoursOfDay.filter { $0.watts != nil }
        Chart(measured) { hour in
            RectangleMark(
                xStart: .value("From", Double(hour.hour) + 0.18), xEnd: .value("To", Double(hour.hour) + 0.82),
                yStart: .value("None", 0), yEnd: .value("Watts", hour.watts ?? 0)
            )
            .cornerRadius(2.5)
            .foregroundStyle(report.busiestHour == nil || hour.hour == report.busiestHour ? tint : tint.opacity(0.4))
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0.0, 6, 12, 18, 24]) { value in
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text(HistoryText.hourLabel(Int(hour) % 24))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let watts = value.as(Double.self) {
                        Text(watts == 0 ? "0 W" : HistoryText.watts(watts))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Power draw through the day"))
        .accessibilityValue(report.busiestHour.map { Text("Busiest around \(HistoryText.hourOfDay($0)).") } ?? Text("No hour stands out."))
    }
}
