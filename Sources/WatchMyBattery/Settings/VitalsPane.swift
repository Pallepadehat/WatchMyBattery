import BatteryKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Battery Health: the battery's vital signs right now, and their history. How warm it ran, how deep it
/// went, what the Mac drew and the charger gave, its voltage, and how its capacity and charge cycles moved.
///
/// Each chart is a bar per hour, day or week spanning the lowest and highest reading, with a tick at the average:
/// the range says more about a battery than an average alone. Hover over one for its numbers. The report is worked
/// out once, when the period or the vitals change, never while drawing.
struct VitalsPane: View {
    let model: AppModel

    @AppStorage("vitalsPeriodDays") private var days = 7
    @State private var report: VitalsReport?
    @State private var now = Date()

    var body: some View {
        let settings = model.settings
        Form {
            if !model.battery.snapshot.hasBattery {
                Section {
                    Text("This Mac has no battery.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    MetricRow(metrics: nowMetrics)
                        .padding(.vertical, 4)
                } header: {
                    Text("Right Now")
                }

                if settings.recordsHistory {
                    if let report {
                        charts(report)
                    } else {
                        Section {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                } else {
                    Section {
                        HistoryRows(model: model)
                    } footer: {
                        Text("Turn on the history to keep the battery's temperature, voltage, power and health over time.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: ReportKey(days: shownDays, revision: model.history.vitalsRevision, hour: Calendar.current.dateInterval(of: .hour, for: now)?.start)) {
            let period = VitalsPeriod(days: shownDays)
            report = model.history.vitals.report(from: period.start(endingAt: now), to: now, granularity: period.granularity)
        }
        .task {
            // The readings the panel shows, while this pane is open, and the clock for the charts' last bar.
            while !Task.isCancelled {
                model.battery.refreshReadings()
                model.battery.refreshHealthIfNeeded()
                now = Date()
                try? await Task.sleep(for: .seconds(5), tolerance: .seconds(1))
            }
        }
    }

    private struct ReportKey: Equatable {
        let days: Int
        let revision: Int
        let hour: Date?
    }

    /// The chosen period, or the longest the history keeps.
    private var shownDays: Int {
        VitalsPeriod.available(keeping: model.settings.historyRetention).contains { $0.days == days }
            ? days : VitalsPeriod.available(keeping: model.settings.historyRetention).last?.days ?? 7
    }

    // MARK: - Right now

    private var nowMetrics: [MetricItem] {
        let readings = model.battery.readings
        let health = model.battery.health
        var metrics = [
            MetricItem(
                title: Text("Temperature"), value: readings?.temperature.map { VitalsText.temperature($0) } ?? "–",
                color: warmthColor(readings?.warmth), help: Text("The battery's own temperature. Around 35 °C while charging is normal.")),
            MetricItem(title: Text("Voltage"), value: readings?.voltage.map(VitalsText.volts) ?? "–"),
        ]
        if let watts = readings?.batteryWatts, abs(watts) >= 0.1 {
            metrics.append(
                MetricItem(
                    title: watts > 0 ? Text("Charging") : Text("Discharging"), value: VitalsText.watts(abs(watts)),
                    symbol: watts > 0 ? "arrow.down" : "arrow.up", color: watts > 0 ? .green : .primary,
                    help: Text("What's going into the battery, or coming out of it.")))
        } else {
            metrics.append(MetricItem(title: Text("Battery"), value: String(localized: "Resting"), help: Text("Neither charging nor running the Mac.")))
        }
        metrics.append(MetricItem(title: Text("Maximum Capacity"), value: health?.maximumCapacity.map(VitalsText.percent) ?? "–"))
        metrics.append(MetricItem(title: Text("Cycles"), value: health?.cycleCount?.formatted() ?? "–"))
        return metrics
    }

    private func warmthColor(_ warmth: BatteryReadings.Warmth?) -> Color {
        switch warmth {
        case .hot: .red
        case .warm: .orange
        default: .primary
        }
    }

    // MARK: - The charts

    @ViewBuilder private func charts(_ report: VitalsReport) -> some View {
        let whole = report.whole
        Section {
            VitalsBlock(metrics: [
                MetricItem(title: Text("Average"), value: whole.temperature.mean.map { VitalsText.temperature($0, digits: 1) } ?? "–"),
                MetricItem(
                    title: Text("Range"),
                    value: whole.temperature.low.flatMap { low in whole.temperature.high.map { VitalsText.range(low, $0, VitalsText.temperatureNumber) } }
                        ?? "–", unit: Text(VitalsText.temperatureUnitSymbol)),
                MetricItem(
                    title: Text("Time Warm"), value: whole.coveredSeconds > 0 ? HistoryText.duration(whole.warmSeconds) : "–",
                    color: whole.warmSeconds >= 3600 ? .orange : .primary,
                    help: Text("About how long the battery was at 38 °C or above, where charging slows down and wear adds up.")),
            ]) {
                RangeChart(
                    report: report, stats: \.temperature, tint: .orange, convert: VitalsText.displayTemperature,
                    format: { VitalsText.temperature($0, converted: false) },
                    threshold: VitalsText.displayTemperature(BatteryReadings.Warmth.warmFrom))
            }
        } header: {
            HStack {
                Text("Temperature")
                Spacer()
                periodPicker
            }
        }

        Section {
            VitalsBlock(metrics: [
                MetricItem(title: Text("Lowest"), value: whole.level.low.map { VitalsText.percent($0 / 100) } ?? "–"),
                MetricItem(title: Text("Average"), value: whole.level.mean.map { VitalsText.percent($0 / 100) } ?? "–"),
                MetricItem(title: Text("On the Charger"), value: report.pluggedInShare.map(VitalsText.percent) ?? "–", unit: Text("of the time")),
            ]) {
                RangeChart(
                    report: report, stats: \.level, tint: .green, convert: { $0 }, format: { VitalsText.percent($0 / 100) }, domain: 0...100)
            }
        } header: {
            Text("Charge Level")
        }

        Section {
            VitalsBlock(metrics: [
                MetricItem(title: Text("Mac Average"), value: whole.system.mean.map(VitalsText.watts) ?? "–"),
                MetricItem(title: Text("Mac Peak"), value: whole.system.high.map(VitalsText.watts) ?? "–"),
                MetricItem(title: Text("Charging Average"), value: whole.charging.mean.map(VitalsText.watts) ?? "–"),
                MetricItem(title: Text("Charger Peak"), value: whole.charger.high.map(VitalsText.watts) ?? "–"),
            ]) {
                PowerChart(report: report)
            }
        } header: {
            Text("Power")
        }

        Section {
            VitalsBlock(metrics: [
                MetricItem(title: Text("Average"), value: whole.voltage.mean.map(VitalsText.volts) ?? "–"),
                MetricItem(
                    title: Text("Range"),
                    value: whole.voltage.low.flatMap { low in whole.voltage.high.map { VitalsText.range(low, $0, VitalsText.voltsNumber) } } ?? "–",
                    unit: Text(verbatim: "V")),
            ]) {
                RangeChart(report: report, stats: \.voltage, tint: .blue, convert: { $0 }, format: VitalsText.volts)
            }
        } header: {
            Text("Voltage")
        } footer: {
            Text("A full battery reads higher, an empty one lower. It drops a little under load and rises while charging.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section {
            VitalsBlock(metrics: healthMetrics(report)) {
                // Read once a day: a day's line would say nothing.
                if report.granularity != .hour { HealthChart(report: report) }
            }
        } header: {
            Text("Health")
        } footer: {
            Text(
                "Read every five minutes, plugged in or not, and kept as long as the history. Health is read once a day and kept for good, so you can see the battery wear over the years."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Section {
            VitalsExportRow(model: model)
        }
    }

    private func healthMetrics(_ report: VitalsReport) -> [MetricItem] {
        let latest = report.health.last
        var metrics = [
            MetricItem(title: Text("Maximum Capacity"), value: latest?.maximumCapacity.map(VitalsText.percent) ?? "–"),
            MetricItem(title: Text("Cycles"), value: latest?.cycleCount?.formatted() ?? "–"),
        ]
        if let change = report.capacityChange {
            let points = (abs(change) * 100).formatted(.number.precision(.fractionLength(0...1)))
            metrics.append(
                MetricItem(
                    title: Text("Capacity Change"), value: change == 0 ? String(localized: "None") : (change < 0 ? "−" : "+") + points,
                    unit: change == 0 ? nil : Text("points"), color: change < 0 ? .orange : .primary))
        }
        if let added = report.cyclesAdded {
            metrics.append(MetricItem(title: Text("Cycles Added"), value: "+" + added.formatted()))
        }
        return metrics
    }

    private var periodPicker: some View {
        Picker("Period", selection: Binding(get: { shownDays }, set: { value in withAnimation(.snappy(duration: 0.25)) { days = value } })) {
            ForEach(VitalsPeriod.available(keeping: model.settings.historyRetention), id: \.days) { period in
                Text(period.title).tag(period.days)
                    .help(Text(period.name))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }
}

/// 24 hours, by the hour, then the History pane's periods.
private struct VitalsPeriod {
    let days: Int

    /// "24H", "7D", "3M", "1Y": short, like the Health app's, so the picker fits beside a section's name.
    var title: LocalizedStringResource {
        switch days {
        case 1: "24H"
        case 90: "3M"
        case 365: "1Y"
        default: "\(days)D"
        }
    }

    /// "24 hours", "3 months", for the picker's help.
    var name: LocalizedStringResource {
        days == 1 ? "24 Hours" : HistoryPeriod(rawValue: days)?.title ?? "\(days) Days"
    }

    var granularity: UsageReport.Granularity {
        days == 1 ? .hour : HistoryPeriod(rawValue: days)?.granularity ?? .day
    }

    func start(endingAt now: Date) -> Date {
        if days == 1 {
            let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
            return hour.addingTimeInterval(-23 * 3600)
        }
        return HistoryPeriod(rawValue: days)?.start(endingAt: now) ?? now.addingTimeInterval(-Double(days) * 24 * 3600)
    }

    static func available(keeping retention: HistoryRetention) -> [VitalsPeriod] {
        [VitalsPeriod(days: 1)] + HistoryPeriod.available(keeping: retention).map { VitalsPeriod(days: $0.rawValue) }
    }
}

/// A row of figures over a chart.
private struct VitalsBlock<Chart: View>: View {
    let metrics: [MetricItem]
    @ViewBuilder let chart: Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricRow(metrics: metrics)
            chart
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Charts

/// What the pointer is over, written above a chart.
private struct HoverCaption: View {
    let text: Text?

    var body: some View {
        (text ?? Text(verbatim: " "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private enum VitalsAxis {
    static func unit(_ granularity: UsageReport.Granularity) -> Calendar.Component {
        switch granularity {
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        }
    }

    static func name(of period: VitalsReport.Period, granularity: UsageReport.Granularity) -> String {
        switch granularity {
        case .hour: period.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .day: period.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .week: String(localized: "Week of \(period.start.formatted(.dateTime.day().month(.abbreviated)))")
        }
    }

    static func period(at date: Date?, in report: VitalsReport) -> VitalsReport.Period? {
        guard let date else { return nil }
        return report.periods.first { $0.start <= date && date < $0.end }
    }

    static func barWidth(_ count: Int) -> MarkDimension { .ratio(count > 45 ? 0.75 : 0.6) }
}

/// A bar from the lowest to the highest reading in each hour, day or week, with a tick at the average.
private struct RangeChart: View {
    let report: VitalsReport
    let stats: KeyPath<VitalsReport.Period, ReadingStats>
    let tint: Color
    /// From what's recorded to what's shown (°C to °F, say).
    let convert: (Double) -> Double
    /// A shown value, as text.
    let format: (Double) -> String
    var threshold: Double?
    var domain: ClosedRange<Double>?

    @State private var hovered: Date?

    var body: some View {
        let unit = VitalsAxis.unit(report.granularity)
        let shown = report.periods.filter { !$0[keyPath: stats].isEmpty }
        let picked = VitalsAxis.period(at: hovered, in: report)
        VStack(alignment: .leading, spacing: 4) {
            HoverCaption(text: caption(picked))
            Chart {
                ForEach(shown) { period in
                    let values = period[keyPath: stats]
                    let low = convert(values.low ?? 0)
                    let high = convert(values.high ?? 0)
                    let isPicked = picked == nil || picked?.start == period.start
                    BarMark(
                        x: .value("Time", period.start, unit: unit), yStart: .value("Lowest", low), yEnd: .value("Highest", max(high, low + span * 0.012)),
                        width: VitalsAxis.barWidth(report.periods.count)
                    )
                    .cornerRadius(2.5)
                    .foregroundStyle(tint.opacity(isPicked ? 0.75 : 0.25))
                    if let mean = values.mean {
                        RectangleMark(
                            x: .value("Time", period.start, unit: unit), y: .value("Average", convert(mean)),
                            width: VitalsAxis.barWidth(report.periods.count), height: .fixed(2)
                        )
                        .foregroundStyle(Color.primary.opacity(isPicked ? 0.7 : 0.25))
                    }
                }
                if let threshold {
                    RuleMark(y: .value("Warm", threshold))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }
            .chartXScale(domain: (report.periods.first?.start ?? Date())...(report.periods.last?.end ?? Date()))
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: HistoryAxis.dates(report.periods.map(\.start), granularity: report.granularity)) { _ in
                    AxisValueLabel(format: HistoryAxis.format(count: report.periods.count, granularity: report.granularity))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(format(number))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartXSelection(value: $hovered)
            .overlay {
                if shown.isEmpty {
                    Text("Readings show here a few minutes after they start.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 130)
            .accessibilityElement(children: .ignore)
            .accessibilityValue(accessibilityValue)
        }
    }

    /// Room around the readings, so a steady line isn't drawn as a flat bar at the very top.
    private var yDomain: ClosedRange<Double> {
        if let domain { return domain }
        let whole = report.whole[keyPath: stats]
        guard var low = whole.low.map(convert), var high = whole.high.map(convert) else { return 0...1 }
        if let threshold {
            low = min(low, threshold)
            high = max(high, threshold)
        }
        let pad = max((high - low) * 0.12, abs(high) * 0.01, 0.1)
        return (low - pad)...(high + pad)
    }

    private var span: Double { yDomain.upperBound - yDomain.lowerBound }

    private func caption(_ period: VitalsReport.Period?) -> Text? {
        guard let period else { return nil }
        let values = period[keyPath: stats]
        let name = Text(VitalsAxis.name(of: period, granularity: report.granularity)).foregroundStyle(.primary)
        guard let low = values.low, let high = values.high, let mean = values.mean else { return Text("\(name)  no readings") }
        return Text("\(name)  \(format(convert(low)))–\(format(convert(high))), avg \(format(convert(mean)))")
    }

    private var accessibilityValue: String {
        let whole = report.whole[keyPath: stats]
        guard let low = whole.low, let high = whole.high else { return String(localized: "No readings yet.") }
        return String(localized: "From \(format(convert(low))) to \(format(convert(high))).")
    }
}

/// What the Mac drew, and what came from the charger, on average in each hour, day or week.
private struct PowerChart: View {
    let report: VitalsReport
    @State private var hovered: Date?

    private static let mac = String(localized: "Mac")
    private static let charger = String(localized: "From Charger")

    var body: some View {
        let unit = VitalsAxis.unit(report.granularity)
        let picked = VitalsAxis.period(at: hovered, in: report)
        VStack(alignment: .leading, spacing: 4) {
            HoverCaption(text: caption(picked))
            Chart {
                ForEach(report.periods.filter { $0.system.mean != nil }) { period in
                    BarMark(
                        x: .value("Time", period.start, unit: unit), y: .value("Watts", period.system.mean ?? 0),
                        width: VitalsAxis.barWidth(report.periods.count)
                    )
                    .cornerRadius(2.5)
                    .foregroundStyle(by: .value("Series", Self.mac))
                    .opacity(picked == nil || picked?.start == period.start ? 1 : 0.35)
                }
                ForEach(report.periods.filter { $0.charger.mean != nil }) { period in
                    LineMark(x: .value("Time", period.start, unit: unit), y: .value("Watts", period.charger.mean ?? 0))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(by: .value("Series", Self.charger))
                }
            }
            .chartForegroundStyleScale([Self.mac: Color.accentColor.opacity(0.8), Self.charger: Color.green])
            .chartLegend(position: .top, alignment: .leading, spacing: 6)
            .chartXScale(domain: (report.periods.first?.start ?? Date())...(report.periods.last?.end ?? Date()))
            .chartXAxis {
                AxisMarks(values: HistoryAxis.dates(report.periods.map(\.start), granularity: report.granularity)) { _ in
                    AxisValueLabel(format: HistoryAxis.format(count: report.periods.count, granularity: report.granularity))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let watts = value.as(Double.self) {
                            Text(VitalsText.watts(watts))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartXSelection(value: $hovered)
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Power"))
            .accessibilityValue(report.whole.system.mean.map { Text("The Mac drew \(VitalsText.watts($0)) on average.") } ?? Text("No readings yet."))
        }
    }

    private func caption(_ period: VitalsReport.Period?) -> Text? {
        guard let period else { return nil }
        let name = Text(VitalsAxis.name(of: period, granularity: report.granularity)).foregroundStyle(.primary)
        var parts: [String] = []
        if let mac = period.system.mean { parts.append(String(localized: "Mac \(VitalsText.watts(mac))")) }
        if let charger = period.charger.mean { parts.append(String(localized: "charger \(VitalsText.watts(charger))")) }
        if let charging = period.charging.mean { parts.append(String(localized: "charging \(VitalsText.watts(charging))")) }
        return Text("\(name)  \(parts.isEmpty ? String(localized: "no readings") : parts.joined(separator: ", "))")
    }
}

/// The maximum capacity, day by day.
private struct HealthChart: View {
    let report: VitalsReport
    @State private var hovered: Date?

    var body: some View {
        let days = report.health.filter { $0.maximumCapacity != nil }
        let picked = hovered.flatMap { date in days.min { abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date)) } }
        VStack(alignment: .leading, spacing: 4) {
            HoverCaption(text: picked.map(caption))
            Chart {
                ForEach(days) { day in
                    let capacity = (day.maximumCapacity ?? 0) * 100
                    AreaMark(x: .value("Day", day.day, unit: .day), yStart: .value("Bottom", yDomain.lowerBound), yEnd: .value("Capacity", capacity))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(.linearGradient(colors: [.pink.opacity(0.25), .pink.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("Capacity", capacity))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(.pink)
                }
                if let picked, let capacity = picked.maximumCapacity {
                    PointMark(x: .value("Day", picked.day, unit: .day), y: .value("Capacity", capacity * 100))
                        .foregroundStyle(.pink)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXScale(domain: (report.periods.first?.start ?? Date())...(report.periods.last?.end ?? Date()))
            .chartXAxis {
                AxisMarks(values: HistoryAxis.dates(report.periods.map(\.start), granularity: report.granularity)) { _ in
                    AxisValueLabel(format: HistoryAxis.format(count: report.periods.count, granularity: report.granularity))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text(VitalsText.percent(percent / 100))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartXSelection(value: $hovered)
            .overlay {
                if days.isEmpty {
                    Text("The battery's health is read once a day. Its line starts with the first reading.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .frame(height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Maximum capacity"))
        }
    }

    /// A few points around the capacity: it moves by a point or two a year, which a 0–100% scale would hide.
    private var yDomain: ClosedRange<Double> {
        let values = report.health.compactMap(\.maximumCapacity).map { $0 * 100 }
        guard let low = values.min(), let high = values.max() else { return 80...100 }
        return (floor(low) - 3)...max(ceil(high) + 1, 100)
    }

    private func caption(_ day: BatteryVitals.HealthDay) -> Text {
        let name = Text(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).foregroundStyle(.primary)
        let capacity = day.maximumCapacity.map(VitalsText.percent) ?? "–"
        if let cycles = day.cycleCount { return Text("\(name)  \(capacity), \(cycles) cycles") }
        return Text("\(name)  \(capacity)")
    }
}

/// Exporting the vitals as CSV, a row an hour.
private struct VitalsExportRow: View {
    let model: AppModel
    @State private var failure: String?

    var body: some View {
        LabeledContent {
            Button("Export…", action: export)
                .disabled(model.history.vitals.isEmpty)
        } label: {
            SettingLabel("Export Battery Vitals", symbol: "square.and.arrow.up.fill", color: .blue) {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(InlineIconLabelStyle(color: .orange))
                } else {
                    Text("A row for every hour, for a spreadsheet: temperature, voltage, power, charge level and health.")
                }
            }
        }
    }

    private func export() {
        failure = nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = HistoryExport.suggestedFileName(.vitalsCSV)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.history.export(.vitalsCSV, sleeps: model.sleep.log).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: - Text

enum VitalsText {
    /// °C or °F, as this Mac's region has it.
    static let temperatureUnit = UnitTemperature(forLocale: .current, usage: .weather)

    static var temperatureUnitSymbol: String { temperatureUnit == .fahrenheit ? "°F" : "°C" }

    /// From °C to the region's unit.
    static func displayTemperature(_ celsius: Double) -> Double {
        Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: temperatureUnit).value
    }

    /// "33 °C"; `converted` is false for a value already in the region's unit.
    static func temperature(_ value: Double, digits: Int = 0, converted: Bool = true) -> String {
        temperatureNumber(converted ? displayTemperature(value) : value, digits: digits) + "°"
    }

    static func temperatureNumber(_ value: Double) -> String { temperatureNumber(displayTemperature(value), digits: 0) }

    private static func temperatureNumber(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func volts(_ volts: Double) -> String { voltsNumber(volts) + " V" }
    static func voltsNumber(_ volts: Double) -> String { volts.formatted(.number.precision(.fractionLength(2))) }

    static func watts(_ watts: Double) -> String {
        watts.formatted(.number.precision(.fractionLength(watts < 10 && watts != 0 ? 1 : 0))) + " W"
    }

    static func percent(_ fraction: Double) -> String { fraction.formatted(.percent.precision(.fractionLength(0))) }

    /// "28–36".
    static func range(_ low: Double, _ high: Double, _ number: (Double) -> String) -> String { "\(number(low))–\(number(high))" }
}
