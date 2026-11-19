import BatteryKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Battery Health: the battery's vital signs right now, and their history. Laid out like System Settings:
/// a short list, a row for each sign (temperature, charge level, power, voltage, health) with a line about it and a
/// sparkline, and a page of its own behind each row, with its chart, its numbers and what to show.
///
/// Each chart is a bar per hour, day or week spanning the lowest and highest reading, with a tick at the average:
/// the range says more about a battery than an average alone. Hover over one for its numbers. The readings can be
/// narrowed to those on battery or plugged in, compared with the period before (a dashed line in each chart, and the
/// change beside each number), and temperature and power seen through the day: each hour of the day, over the period.
/// Reports are worked out once, when something they depend on changes, never while drawing.
struct VitalsPane: View {
    let model: AppModel

    @AppStorage("vitalsPeriodDays") private var days = 7
    @AppStorage("vitalsFilter") private var filter = VitalsFilter.all
    @AppStorage("vitalsCompares") private var compares = false
    @State private var page: VitalsPage?
    @State private var temperatureMode = ChartMode.overTime
    @State private var powerMode = ChartMode.overTime
    @State private var reports: Reports?
    @State private var now = Date()

    /// `page` opens one of the pages, and `throughTheDay` shows temperature and power through the day, for previews.
    init(model: AppModel, page: VitalsPage? = nil, throughTheDay: Bool = false) {
        self.model = model
        _page = State(initialValue: page)
        _temperatureMode = State(initialValue: throughTheDay ? .throughTheDay : .overTime)
        _powerMode = State(initialValue: throughTheDay ? .throughTheDay : .overTime)
    }

    private struct Reports {
        let current: VitalsReport
        /// The same length of time just before, when comparing.
        let previous: VitalsReport?
    }

    var body: some View {
        ZStack {
            if let page {
                detail(page)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                overview
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .task(id: ReportKey(days: shownDays, filter: filter, compares: compares, revision: model.history.vitalsRevision, hour: hour)) {
            let period = VitalsPeriod(days: shownDays)
            let vitals = model.history.vitals
            let start = period.start(endingAt: now)
            let current = vitals.report(from: start, to: now, granularity: period.granularity, filter: filter)
            var previous: VitalsReport?
            if compares {
                let before = period.start(before: start)
                previous = vitals.report(from: before, to: start, granularity: period.granularity, filter: filter)
            }
            reports = Reports(current: current, previous: previous)
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

    private func show(_ page: VitalsPage?) {
        withAnimation(.smooth(duration: 0.35)) { self.page = page }
    }

    private struct ReportKey: Equatable {
        let days: Int
        let filter: VitalsFilter
        let compares: Bool
        let revision: Int
        let hour: Date?
    }

    private var hour: Date? { Calendar.current.dateInterval(of: .hour, for: now)?.start }

    /// The chosen period, or the longest the history keeps.
    private var shownDays: Int {
        let available = VitalsPeriod.available(keeping: model.settings.historyRetention)
        return available.contains { $0.days == days } ? days : available.last?.days ?? 7
    }

    // MARK: - The list

    private var overview: some View {
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

                if model.settings.recordsHistory {
                    Section {
                        ForEach(VitalsPage.allCases) { page in
                            VitalsRow(
                                page: page, summary: reports.flatMap { summary(of: page, in: $0.current) },
                                values: reports.map { sparkline(of: page, in: $0.current) } ?? []
                            ) {
                                show(page)
                            }
                        }
                    } header: {
                        HStack {
                            Text("History")
                            Spacer()
                            periodPicker
                        }
                    } footer: {
                        Text("Read every five minutes, plugged in or not, and kept as long as the history. Health is read once a day and kept for good.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        VitalsExportRow(model: model)
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
    }

    /// A row's line: what the period says about it, in a few words.
    private func summary(of page: VitalsPage, in report: VitalsReport) -> String? {
        let whole = report.whole.stats
        switch page {
        case .temperature:
            guard let mean = whole.temperature.mean, let high = whole.temperature.high else { return nil }
            return String(localized: "Average \(VitalsText.temperature(mean)), up to \(VitalsText.temperature(high))")
        case .level:
            guard let low = whole.level.low, let share = report.pluggedInShare else { return nil }
            return String(localized: "Down to \(VitalsText.percent(low / 100)), on the charger \(VitalsText.percent(share)) of the time")
        case .power:
            guard let mean = whole.system.mean, let high = whole.system.high else { return nil }
            return String(localized: "The Mac drew \(VitalsText.watts(mean)) on average, up to \(VitalsText.watts(high))")
        case .voltage:
            guard let low = whole.voltage.low, let high = whole.voltage.high else { return nil }
            return String(localized: "Between \(VitalsText.volts(low)) and \(VitalsText.volts(high))")
        case .health:
            let latest = report.health.last ?? report.healthBefore
            guard let capacity = latest?.maximumCapacity else { return nil }
            if let cycles = latest?.cycleCount {
                return String(localized: "\(VitalsText.percent(capacity)) maximum capacity, \(cycles) cycles")
            }
            return String(localized: "\(VitalsText.percent(capacity)) maximum capacity")
        }
    }

    /// A row's sparkline: the average in each hour, day or week.
    private func sparkline(of page: VitalsPage, in report: VitalsReport) -> [Double] {
        switch page {
        case .temperature: report.periods.compactMap(\.stats.temperature.mean)
        case .level: report.periods.compactMap(\.stats.level.mean)
        case .power: report.periods.compactMap(\.stats.system.mean)
        case .voltage: report.periods.compactMap(\.stats.voltage.mean)
        case .health: report.health.compactMap(\.maximumCapacity)
        }
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

    private var periodPicker: some View {
        Picker("Period", selection: Binding(get: { shownDays }, set: { value in withAnimation(.snappy(duration: 0.25)) { days = value } })) {
            ForEach(VitalsPeriod.available(keeping: model.settings.historyRetention), id: \.days) { period in
                Text(period.title).tag(period.days)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    // MARK: - A page

    private func detail(_ page: VitalsPage) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(page: page, summary: reports.flatMap { summary(of: page, in: $0.current) })
                    if let reports {
                        content(page, reports.current, previous: reports.previous)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Button {
                        show(nil)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Battery Health")
                        }
                    }
                    .buttonStyle(.link)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back to Battery Health (⌘[)")
                    Spacer()
                    periodPicker
                }
            }

            if page != .health {
                Section {
                    if page == .temperature || page == .power {
                        Picker(
                            selection: page == .temperature
                                ? $temperatureMode.animation(.snappy(duration: 0.25)) : $powerMode.animation(.snappy(duration: 0.25))
                        ) {
                            Text("Over Time").tag(ChartMode.overTime)
                            Text("Through the Day").tag(ChartMode.throughTheDay)
                        } label: {
                            SettingLabel("Chart", symbol: "chart.bar.fill", color: page.color)
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker(selection: $filter.animation(.snappy(duration: 0.25))) {
                        Text("All").tag(VitalsFilter.all)
                        Text("On Battery").tag(VitalsFilter.onBattery)
                        Text("Plugged In").tag(VitalsFilter.pluggedIn)
                    } label: {
                        SettingLabel("Readings", symbol: "line.3.horizontal.decrease", color: .blue)
                    }
                    .pickerStyle(.segmented)
                    Toggle(isOn: $compares.animation(.snappy(duration: 0.25))) {
                        SettingLabel("Compare with Before", symbol: "arrow.left.arrow.right", color: .gray) {
                            Text("The period before as a dashed line, and how much each number changed.")
                        }
                    }
                } header: {
                    Text("Show")
                }
            }

            Section {
                Text(page.about)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("About")
            }
        }
        .onExitCommand { show(nil) }
    }

    @ViewBuilder private func content(_ page: VitalsPage, _ report: VitalsReport, previous: VitalsReport?) -> some View {
        let whole = report.whole.stats
        let before = previous?.whole.stats
        switch page {
        case .temperature:
            MetricRow(metrics: [
                MetricItem(
                    title: Text("Average"), value: whole.temperature.mean.map { VitalsText.temperature($0, digits: 1) } ?? "–",
                    change: VitalsChange.text(
                        whole.temperature.mean.map(VitalsText.displayTemperature), before?.temperature.mean.map(VitalsText.displayTemperature),
                        suffix: "°", digits: 1, higherIsWorse: true)),
                MetricItem(
                    title: Text("Range"),
                    value: whole.temperature.low.flatMap { low in whole.temperature.high.map { VitalsText.range(low, $0, VitalsText.temperatureNumber) } }
                        ?? "–", unit: Text(VitalsText.temperatureUnitSymbol)),
                MetricItem(
                    title: Text("Time Warm"), value: report.whole.coveredSeconds > 0 ? HistoryText.duration(report.whole.warmSeconds) : "–",
                    color: report.whole.warmSeconds >= 3600 ? .orange : .primary,
                    help: Text("About how long the battery was at 38 °C or above, where charging slows down and wear adds up."),
                    change: previous.flatMap { VitalsChange.duration(report.whole.warmSeconds, $0.whole.warmSeconds) }),
            ])
            Divider()
            switch temperatureMode {
            case .overTime:
                RangeChart(
                    report: report, previous: previous, stats: \.temperature, tint: page.color, convert: VitalsText.displayTemperature,
                    format: { VitalsText.temperature($0, converted: false) }, threshold: VitalsText.displayTemperature(BatteryReadings.Warmth.warmFrom),
                    height: 190)
            case .throughTheDay:
                HourOfDayChart(
                    report: report, previous: previous, stats: \.temperature, tint: page.color, convert: VitalsText.displayTemperature,
                    format: { VitalsText.temperature($0, converted: false) }, threshold: VitalsText.displayTemperature(BatteryReadings.Warmth.warmFrom),
                    summary: report.warmestHour.map { Text("Warmest around \(HistoryText.hourOfDay($0))") })
            }
        case .level:
            MetricRow(metrics: [
                MetricItem(
                    title: Text("Lowest"), value: whole.level.low.map { VitalsText.percent($0 / 100) } ?? "–",
                    change: VitalsChange.text(whole.level.low, before?.level.low, suffix: "%", digits: 0, higherIsWorse: false)),
                MetricItem(
                    title: Text("Average"), value: whole.level.mean.map { VitalsText.percent($0 / 100) } ?? "–",
                    change: VitalsChange.text(whole.level.mean, before?.level.mean, suffix: "%", digits: 0, higherIsWorse: nil)),
                MetricItem(
                    title: Text("On the Charger"), value: report.pluggedInShare.map(VitalsText.percent) ?? "–", unit: Text("of the time"),
                    change: VitalsChange.text(
                        report.pluggedInShare.map { $0 * 100 }, previous?.pluggedInShare.map { $0 * 100 }, suffix: "%", digits: 0, higherIsWorse: nil)),
            ])
            Divider()
            RangeChart(
                report: report, previous: previous, stats: \.level, tint: page.color, convert: { $0 }, format: { VitalsText.percent($0 / 100) },
                domain: 0...100, height: 190)
        case .power:
            MetricRow(metrics: [
                MetricItem(
                    title: Text("Mac Average"), value: whole.system.mean.map(VitalsText.watts) ?? "–",
                    change: VitalsChange.text(whole.system.mean, before?.system.mean, suffix: " W", digits: 1, higherIsWorse: true)),
                MetricItem(
                    title: Text("Mac Peak"), value: whole.system.high.map(VitalsText.watts) ?? "–",
                    change: VitalsChange.text(whole.system.high, before?.system.high, suffix: " W", digits: 0, higherIsWorse: true)),
                MetricItem(title: Text("Charging Average"), value: whole.charging.mean.map(VitalsText.watts) ?? "–"),
                MetricItem(title: Text("Charger Peak"), value: whole.charger.high.map(VitalsText.watts) ?? "–"),
            ])
            Divider()
            switch powerMode {
            case .overTime:
                PowerChart(report: report, previous: previous)
            case .throughTheDay:
                HourOfDayChart(
                    report: report, previous: previous, stats: \.system, tint: page.color, convert: { $0 }, format: VitalsText.watts,
                    summary: report.busiestHour.map { Text("Busiest around \(HistoryText.hourOfDay($0))") })
            }
        case .voltage:
            MetricRow(metrics: [
                MetricItem(
                    title: Text("Average"), value: whole.voltage.mean.map(VitalsText.volts) ?? "–",
                    change: VitalsChange.text(whole.voltage.mean, before?.voltage.mean, suffix: " V", digits: 2, higherIsWorse: nil)),
                MetricItem(
                    title: Text("Range"),
                    value: whole.voltage.low.flatMap { low in whole.voltage.high.map { VitalsText.range(low, $0, VitalsText.voltsNumber) } } ?? "–",
                    unit: Text(verbatim: "V")),
            ])
            Divider()
            RangeChart(report: report, previous: previous, stats: \.voltage, tint: page.color, convert: { $0 }, format: VitalsText.volts, height: 190)
        case .health:
            MetricRow(metrics: healthMetrics(report))
            if report.granularity != .hour {
                Divider()
                HealthChart(report: report)
            }
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
}

/// The pages behind Battery Health's rows.
enum VitalsPage: String, CaseIterable, Identifiable {
    case temperature, level, power, voltage, health

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .temperature: "Temperature"
        case .level: "Charge Level"
        case .power: "Power"
        case .voltage: "Voltage"
        case .health: "Health"
        }
    }

    var symbol: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .level: "battery.75percent"
        case .power: "bolt.fill"
        case .voltage: "waveform.path.ecg"
        case .health: "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .temperature: .orange
        case .level: .green
        case .power: .blue
        case .voltage: .teal
        case .health: .pink
        }
    }

    /// What the page is about, and what's good to know.
    var about: LocalizedStringKey {
        switch self {
        case .temperature:
            "The battery's own temperature, from its sensors. Around 35 °C while charging is normal. From 38 °C, charging slows down and time spent this warm wears a battery faster; from 40 °C, macOS holds back charging. Keeping the Mac out of the sun and off soft surfaces while it charges helps."
        case .level:
            "How low and high the charge went in each hour, day or week. Batteries last longest kept between about 20 and 80 percent; a charge limit (Settings › Charging) keeps the top end down for you."
        case .power:
            "What the whole Mac drew, and what came in from the charger. The difference, plugged in, is what charged the battery; when the Mac draws more than the charger gives, the battery makes up the rest."
        case .voltage:
            "A full battery reads higher, an empty one lower. It drops a little under load and rises while charging. Over months, the voltage at the same charge level drifts a little lower as a battery wears."
        case .health:
            "The battery's maximum capacity against when it was new, and its charge cycles: a cycle is a full battery used, in one go or over several days. Read once a day from macOS's own figures, and kept for good, so you can see the battery wear over the years."
        }
    }
}

/// A row in Battery Health's list, like a row in System Settings: an icon, a name over a line about it, a sparkline,
/// and a chevron to its page.
private struct VitalsRow: View {
    let page: VitalsPage
    let summary: String?
    let values: [Double]
    let open: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                SettingIcon(symbol: page.symbol, color: page.color, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(page.title)
                    Text(summary ?? String(localized: "No readings in this time yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                Sparkline(values: values, tint: page.color)
                    .frame(width: 72, height: 24)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(page.title))
        .accessibilityValue(summary ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// A small line of the averages, with no axes: the shape of the period at a glance.
private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        if values.count >= 2, let low = values.min(), let high = values.max() {
            let pad = max((high - low) * 0.15, abs(high) * 0.005, 0.01)
            Chart(values.indices, id: \.self) { index in
                AreaMark(x: .value("Index", index), yStart: .value("Bottom", low - pad), yEnd: .value("Value", values[index]))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [tint.opacity(0.3), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Index", index), y: .value("Value", values[index]))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartLegend(.hidden)
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

/// A page's top: its icon, big, and its name over the line its row has.
private struct PageHeader: View {
    let page: VitalsPage
    let summary: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingIcon(symbol: page.symbol, color: page.color, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .font(.title3.weight(.semibold))
                if let summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A chart over the period, or through the day.
private enum ChartMode: Hashable {
    case overTime
    case throughTheDay
}

/// 24 hours, by the hour, then the History pane's periods.
private struct VitalsPeriod {
    let days: Int

    /// "24H", "7D", "3M", "1Y": short, like the Health app's.
    var title: LocalizedStringResource {
        switch days {
        case 1: "24H"
        case 90: "3M"
        case 365: "1Y"
        default: "\(days)D"
        }
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

    /// Where the same length of time before `start` begins.
    func start(before start: Date) -> Date {
        if days == 1 { return start.addingTimeInterval(-24 * 3600) }
        return Calendar.current.date(byAdding: .day, value: -days, to: start) ?? start.addingTimeInterval(-Double(days) * 24 * 3600)
    }

    static func available(keeping retention: HistoryRetention) -> [VitalsPeriod] {
        [VitalsPeriod(days: 1)] + HistoryPeriod.available(keeping: retention).map { VitalsPeriod(days: $0.rawValue) }
    }
}

/// How much a number changed since the period before: "▲ 1.2°", orange where higher is worse.
private enum VitalsChange {
    static func text(_ now: Double?, _ before: Double?, suffix: String, digits: Int, higherIsWorse: Bool?) -> Text? {
        guard let now, let before else { return nil }
        let change = now - before
        let step = pow(10, -Double(digits))
        guard abs(change) >= step / 2 else { return Text("Same").foregroundStyle(.secondary) }
        let amount = abs(change).formatted(.number.precision(.fractionLength(digits))) + suffix
        return arrow(change > 0, amount: amount, isWorse: higherIsWorse.map { $0 == (change > 0) })
    }

    static func duration(_ now: TimeInterval, _ before: TimeInterval) -> Text? {
        let change = now - before
        guard abs(change) >= 60 else { return Text("Same").foregroundStyle(.secondary) }
        return arrow(change > 0, amount: HistoryText.duration(abs(change)), isWorse: change > 0)
    }

    private static func arrow(_ up: Bool, amount: String, isWorse: Bool?) -> Text {
        let color: Color =
            switch isWorse {
            case true?: .orange
            case false?: .green
            case nil: .secondary
            }
        return Text("\(Image(systemName: up ? "arrow.up" : "arrow.down"))\(amount)").foregroundStyle(color)
    }
}

// MARK: - Charts

/// What the pointer is over, or what the chart says, written above it.
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

    static func index(at date: Date?, in report: VitalsReport) -> Int? {
        guard let date else { return nil }
        return report.periods.firstIndex { $0.start <= date && date < $0.end }
    }

    static func barWidth(_ count: Int) -> MarkDimension { .ratio(count > 45 ? 0.75 : 0.6) }

    /// The period before's value at the same place: its `index`th hour, day or week.
    static func before(_ previous: VitalsReport?, at index: Int) -> VitalsReport.Period? {
        guard let previous, previous.periods.indices.contains(index) else { return nil }
        return previous.periods[index]
    }

    static let beforeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])
    static let beforeName = String(localized: "Before")
}

/// The y axis's room around some readings, so a steady line isn't drawn as a flat bar at the very top.
private func paddedDomain(_ values: [Double], including threshold: Double?) -> ClosedRange<Double> {
    var values = values
    if let threshold { values.append(threshold) }
    guard let low = values.min(), let high = values.max() else { return 0...1 }
    let pad = max((high - low) * 0.12, abs(high) * 0.01, 0.1)
    return (low - pad)...(high + pad)
}

/// A bar from the lowest to the highest reading in each hour, day or week, with a tick at the average, and the period
/// before's averages as a dashed line when comparing.
private struct RangeChart: View {
    let report: VitalsReport
    let previous: VitalsReport?
    let stats: KeyPath<VitalsStats, ReadingStats>
    let tint: Color
    /// From what's recorded to what's shown (°C to °F, say).
    let convert: (Double) -> Double
    /// A shown value, as text.
    let format: (Double) -> String
    var threshold: Double?
    var domain: ClosedRange<Double>?
    var height: CGFloat = 130

    @State private var hovered: Date?

    var body: some View {
        let unit = VitalsAxis.unit(report.granularity)
        let periods = report.periods
        let picked = VitalsAxis.index(at: hovered, in: report)
        let isEmpty = report.whole.stats[keyPath: stats].isEmpty
        VStack(alignment: .leading, spacing: 4) {
            HoverCaption(text: caption(picked))
            Chart {
                ForEach(periods.indices, id: \.self) { index in
                    let period = periods[index]
                    let values = period.stats[keyPath: stats]
                    if let low = values.low.map(convert), let high = values.high.map(convert) {
                        let isPicked = picked == nil || picked == index
                        BarMark(
                            x: .value("Time", period.start, unit: unit), yStart: .value("Lowest", low),
                            yEnd: .value("Highest", max(high, low + span * 0.012)), width: VitalsAxis.barWidth(periods.count)
                        )
                        .cornerRadius(2.5)
                        .foregroundStyle(tint.opacity(isPicked ? 0.75 : 0.25))
                        if let mean = values.mean {
                            RectangleMark(
                                x: .value("Time", period.start, unit: unit), y: .value("Average", convert(mean)),
                                width: VitalsAxis.barWidth(periods.count), height: .fixed(2)
                            )
                            .foregroundStyle(Color.primary.opacity(isPicked ? 0.7 : 0.25))
                        }
                    }
                    if let mean = VitalsAxis.before(previous, at: index)?.stats[keyPath: stats].mean {
                        LineMark(x: .value("Time", period.start, unit: unit), y: .value("Before", convert(mean)), series: .value("Series", "before"))
                            .interpolationMethod(.monotone)
                            .lineStyle(VitalsAxis.beforeStyle)
                            .foregroundStyle(Color.secondary)
                    }
                }
                if let threshold {
                    RuleMark(y: .value("Warm", threshold))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }
            .chartXScale(domain: (periods.first?.start ?? Date())...(periods.last?.end ?? Date()))
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: HistoryAxis.dates(periods.map(\.start), granularity: report.granularity)) { _ in
                    AxisValueLabel(format: HistoryAxis.format(count: periods.count, granularity: report.granularity))
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
                if isEmpty {
                    Text("No readings in this time yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityValue(accessibilityValue)
        }
    }

    private var yDomain: ClosedRange<Double> {
        if let domain { return domain }
        let mine = report.whole.stats[keyPath: stats]
        let theirs = previous?.whole.stats[keyPath: stats]
        let values = [mine.low, mine.high, theirs?.mean].compactMap { $0.map(convert) }
        return paddedDomain(values, including: threshold)
    }

    private var span: Double { yDomain.upperBound - yDomain.lowerBound }

    private func caption(_ index: Int?) -> Text? {
        guard let index else { return nil }
        let period = report.periods[index]
        let values = period.stats[keyPath: stats]
        let name = Text(VitalsAxis.name(of: period, granularity: report.granularity)).foregroundStyle(.primary)
        let before = VitalsAxis.before(previous, at: index)?.stats[keyPath: stats].mean.map { String(localized: ", before \(format(convert($0)))") } ?? ""
        guard let low = values.low, let high = values.high, let mean = values.mean else { return Text("\(name)  no readings") }
        return Text("\(name)  \(format(convert(low)))–\(format(convert(high))), avg \(format(convert(mean)))\(before)")
    }

    private var accessibilityValue: String {
        let whole = report.whole.stats[keyPath: stats]
        guard let low = whole.low, let high = whole.high else { return String(localized: "No readings yet.") }
        return String(localized: "From \(format(convert(low))) to \(format(convert(high))).")
    }
}

/// Each hour of the day over the whole period: the range of readings in it, and their average. When in the day the
/// battery runs warm, or the Mac draws the most.
private struct HourOfDayChart: View {
    let report: VitalsReport
    let previous: VitalsReport?
    let stats: KeyPath<VitalsStats, ReadingStats>
    let tint: Color
    let convert: (Double) -> Double
    let format: (Double) -> String
    var threshold: Double?
    /// What the chart says, when the pointer isn't on it.
    var summary: Text?

    @State private var hovered: Double?

    var body: some View {
        let hours = report.hoursOfDay
        let picked = hovered.map { min(max(Int($0), 0), 23) }
        VStack(alignment: .leading, spacing: 4) {
            HoverCaption(text: picked.map(caption) ?? summary)
            Chart {
                ForEach(hours) { hour in
                    let values = hour.stats[keyPath: stats]
                    let x = Double(hour.hour)
                    if let low = values.low.map(convert), let high = values.high.map(convert) {
                        let isPicked = picked == nil || picked == hour.hour
                        RectangleMark(
                            xStart: .value("From", x + 0.18), xEnd: .value("To", x + 0.82), yStart: .value("Lowest", low),
                            yEnd: .value("Highest", max(high, low + span * 0.012))
                        )
                        .cornerRadius(2.5)
                        .foregroundStyle(tint.opacity(isPicked ? 0.75 : 0.25))
                        if let mean = values.mean {
                            RectangleMark(
                                xStart: .value("From", x + 0.18), xEnd: .value("To", x + 0.82), y: .value("Average", convert(mean)), height: .fixed(2)
                            )
                            .foregroundStyle(Color.primary.opacity(isPicked ? 0.7 : 0.25))
                        }
                    }
                }
                if let previous {
                    ForEach(previous.hoursOfDay) { hour in
                        if let mean = hour.stats[keyPath: stats].mean {
                            LineMark(x: .value("Hour", Double(hour.hour) + 0.5), y: .value("Before", convert(mean)), series: .value("Series", "before"))
                                .interpolationMethod(.monotone)
                                .lineStyle(VitalsAxis.beforeStyle)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                if let threshold {
                    RuleMark(y: .value("Warm", threshold))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }
            .chartXScale(domain: 0...24)
            .chartYScale(domain: yDomain)
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
                        if let number = value.as(Double.self) {
                            Text(format(number))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartXSelection(value: $hovered)
            .overlay {
                if report.whole.stats[keyPath: stats].isEmpty {
                    Text("No readings in this time yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 190)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Through the day"))
            .accessibilityValue(summary ?? Text(verbatim: ""))
        }
    }

    private var yDomain: ClosedRange<Double> {
        let mine = report.hoursOfDay.flatMap { [$0.stats[keyPath: stats].low, $0.stats[keyPath: stats].high] }
        let theirs = previous?.hoursOfDay.map { $0.stats[keyPath: stats].mean } ?? []
        return paddedDomain((mine + theirs).compactMap { $0.map(convert) }, including: threshold)
    }

    private var span: Double { yDomain.upperBound - yDomain.lowerBound }

    private func caption(_ hour: Int) -> Text {
        let values = report.hoursOfDay[hour].stats[keyPath: stats]
        let name = Text(HistoryText.hourOfDay(hour)).foregroundStyle(.primary)
        let before =
            previous.flatMap { $0.hoursOfDay[hour].stats[keyPath: stats].mean }.map { String(localized: ", before \(format(convert($0)))") } ?? ""
        guard let low = values.low, let high = values.high, let mean = values.mean else { return Text("\(name)  no readings") }
        return Text("\(name)  \(format(convert(low)))–\(format(convert(high))), avg \(format(convert(mean)))\(before)")
    }
}

/// What the Mac drew, and what came from the charger, on average in each hour, day or week.
private struct PowerChart: View {
    let report: VitalsReport
    let previous: VitalsReport?
    @State private var hovered: Date?

    private static let mac = String(localized: "Mac")
    private static let charger = String(localized: "From Charger")

    var body: some View {
        let unit = VitalsAxis.unit(report.granularity)
        let periods = report.periods
        let picked = VitalsAxis.index(at: hovered, in: report)
        VStack(alignment: .leading, spacing: 4) {
            HoverCaption(text: caption(picked))
            Chart {
                ForEach(periods.indices, id: \.self) { index in
                    let period = periods[index]
                    if let mac = period.stats.system.mean {
                        BarMark(x: .value("Time", period.start, unit: unit), y: .value("Watts", mac), width: VitalsAxis.barWidth(periods.count))
                            .cornerRadius(2.5)
                            .foregroundStyle(by: .value("Series", Self.mac))
                            .opacity(picked == nil || picked == index ? 1 : 0.35)
                    }
                    if let charger = period.stats.charger.mean {
                        LineMark(x: .value("Time", period.start, unit: unit), y: .value("Watts", charger), series: .value("Line", "charger"))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(by: .value("Series", Self.charger))
                    }
                    if let before = VitalsAxis.before(previous, at: index)?.stats.system.mean {
                        LineMark(x: .value("Time", period.start, unit: unit), y: .value("Watts", before), series: .value("Line", "before"))
                            .interpolationMethod(.monotone)
                            .lineStyle(VitalsAxis.beforeStyle)
                            .foregroundStyle(by: .value("Series", VitalsAxis.beforeName))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: previous == nil ? [Self.mac, Self.charger] : [Self.mac, Self.charger, VitalsAxis.beforeName],
                range: previous == nil ? [Color.accentColor.opacity(0.8), .green] : [Color.accentColor.opacity(0.8), .green, .secondary]
            )
            .chartLegend(position: .top, alignment: .leading, spacing: 6)
            .chartXScale(domain: (periods.first?.start ?? Date())...(periods.last?.end ?? Date()))
            .chartXAxis {
                AxisMarks(values: HistoryAxis.dates(periods.map(\.start), granularity: report.granularity)) { _ in
                    AxisValueLabel(format: HistoryAxis.format(count: periods.count, granularity: report.granularity))
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
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Power"))
            .accessibilityValue(report.whole.stats.system.mean.map { Text("The Mac drew \(VitalsText.watts($0)) on average.") } ?? Text("No readings yet."))
        }
    }

    private func caption(_ index: Int?) -> Text? {
        guard let index else { return nil }
        let period = report.periods[index]
        let name = Text(VitalsAxis.name(of: period, granularity: report.granularity)).foregroundStyle(.primary)
        var parts: [String] = []
        if let mac = period.stats.system.mean { parts.append(String(localized: "Mac \(VitalsText.watts(mac))")) }
        if let charger = period.stats.charger.mean { parts.append(String(localized: "charger \(VitalsText.watts(charger))")) }
        if let charging = period.stats.charging.mean { parts.append(String(localized: "charging \(VitalsText.watts(charging))")) }
        if let before = VitalsAxis.before(previous, at: index)?.stats.system.mean {
            parts.append(String(localized: "before \(VitalsText.watts(before))"))
        }
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
            .frame(height: 170)
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

    /// "33°"; `converted` is false for a value already in the region's unit.
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
