import BatteryKit
import Charts
import SwiftUI

/// Settings › Stats' tabs: everything WatchMyBattery has measured, in one place.
enum StatsTab: String, CaseIterable, Identifiable {
    case usage, charging, health, sleep

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .usage: "Usage"
        case .charging: "Charging"
        case .health: "Health"
        case .sleep: "Sleep"
        }
    }

    var symbol: String {
        switch self {
        case .usage: "chart.bar.fill"
        case .charging: "bolt.fill"
        case .health: "heart.fill"
        case .sleep: "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .usage: .blue
        case .charging: .green
        case .health: .pink
        case .sleep: .purple
        }
    }
}

/// Settings › Stats: the battery's use and the apps behind it, its time on the charger, its health, and its sleeps,
/// a tab each, so it's all in one place rather than a pane apiece.
struct StatsPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            StatsTabBar(selection: $model.statsTab)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 2)
            Group {
                switch model.statsTab {
                case .usage: HistoryPane(model: model)
                case .charging: ChargingStats(model: model)
                case .health: VitalsPane(model: model)
                case .sleep: SleepStats(model: model)
                }
            }
            .frame(maxHeight: .infinity)
            .id(model.statsTab)
            .transition(.opacity)
        }
        // The forms' own grouped background, under the tabs too, so they sit on one surface.
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The four tabs as tiles, each with its own colour, the chosen one lifted onto a card that slides between them.
private struct StatsTabBar: View {
    @Binding var selection: StatsTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsTab.allCases) { tab in
                StatsTabButton(tab: tab, isSelected: tab == selection, namespace: namespace) {
                    withAnimation(.snappy(duration: 0.3)) { selection = tab }
                }
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stats")
    }
}

private struct StatsTabButton: View {
    let tab: StatsTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(tab.color.gradient, in: .rect(cornerRadius: 6, style: .continuous))
                    .opacity(isSelected || isHovered ? 1 : 0.75)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Shared pieces

/// A friendly empty tab: a big symbol, what will show here, and sometimes a button to get it going.
struct StatsEmptyState<Actions: View>: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actions: Actions

    init(
        symbol: String, color: Color, title: LocalizedStringKey, message: LocalizedStringKey, @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(color.gradient, in: .circle)
                .shadow(color: color.opacity(0.35), radius: 8, y: 3)
                .padding(.bottom, 4)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

extension StatsEmptyState where Actions == EmptyView {
    init(symbol: String, color: Color, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(symbol: symbol, color: color, title: title, message: message) { EmptyView() }
    }
}

/// What a tab shows while the history is off: what it would show, and the switch.
struct HistoryOffSection: View {
    let model: AppModel

    var body: some View {
        Section {
            StatsEmptyState(
                symbol: "chart.xyaxis.line", color: .pink, title: "Turn On the History",
                message: "Keep the battery's level, the apps that used it, its charging and its health, hour by hour. It stays on this Mac."
            ) {
                Button("Turn On History") { model.settings.recordsHistory = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Charging

/// The kinds of time a ``ChargeTime`` tells apart, each with its colour.
private enum ChargeKind: CaseIterable, Identifiable {
    case onBattery, charging, holding, full

    var id: Self { self }

    var title: String {
        switch self {
        case .onBattery: String(localized: "On Battery")
        case .charging: String(localized: "Charging")
        case .holding: String(localized: "Held at Limit")
        case .full: String(localized: "Sitting Full")
        }
    }

    var color: Color {
        switch self {
        case .onBattery: .blue
        case .charging: .green
        case .holding: .teal
        case .full: .orange
        }
    }

    var help: String {
        switch self {
        case .onBattery: String(localized: "Awake and running on the battery.")
        case .charging: String(localized: "On the charger, with the battery charging.")
        case .holding: String(localized: "On the charger, with the battery held below full by a charge limit or Optimized Battery Charging.")
        case .full: String(localized: "On the charger with the battery full, where a battery wears fastest.")
        }
    }

    func seconds(_ time: ChargeTime) -> Double {
        switch self {
        case .onBattery: time.onBattery
        case .charging: time.charging
        case .holding: time.holding
        case .full: time.full
        }
    }
}

/// Stats › Charging: how long the Mac spends on the charger, and what the battery does there: charging, held at its
/// limit, or sitting full. How often it reaches its limit, and how long it stays plugged in after. And, from that,
/// what would be kinder to the battery.
struct ChargingStats: View {
    let model: AppModel

    @AppStorage("chargingStatsDays") private var days = 7
    @State private var report: VitalsReport?
    @State private var now = Date()

    var body: some View {
        Form {
            if !model.battery.snapshot.hasBattery {
                Section {
                    Text("This Mac has no battery.")
                        .foregroundStyle(.secondary)
                }
            } else if !model.settings.recordsHistory {
                HistoryOffSection(model: model)
            } else {
                Section {
                    if let report {
                        let time = report.whole.charge
                        if time.isEmpty {
                            StatsEmptyState(
                                symbol: "bolt.fill", color: .green, title: "Charging Stats Start Now",
                                message:
                                    "Every few minutes, WatchMyBattery notes whether your Mac is on battery, charging, held at its limit or sitting full. Check back once it's been on the charger for a while."
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                ChargeSplit(time: time)
                                Divider()
                                MetricRow(metrics: metrics(time, report: report))
                                ChargeTimeChart(report: report)
                            }
                            .padding(.vertical, 6)
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                } header: {
                    HStack {
                        Text("Where the Time Went")
                        Spacer()
                        periodPicker
                    }
                } footer: {
                    Text("From a reading every five minutes while the Mac is awake, from WatchMyBattery 0.5.1 on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let report, !report.whole.charge.isEmpty {
                    let notes = careNotes(report.whole.charge)
                    if !notes.isEmpty {
                        Section {
                            ForEach(notes) { note in
                                CareNoteRow(note: note)
                            }
                        } header: {
                            Text("Battery Care")
                        }
                    }
                }

                Section {
                    ChargeLimitStatusRow(model: model)
                }
            }
        }
        .task(id: Key(days: shownDays, revision: model.history.vitalsRevision, hour: Calendar.current.dateInterval(of: .hour, for: now)?.start)) {
            let period = VitalsPeriod(days: shownDays)
            report = model.history.vitals.report(from: period.start(endingAt: now), to: now, granularity: period.granularity)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
                now = Date()
            }
        }
    }

    private struct Key: Equatable {
        let days: Int
        let revision: Int
        let hour: Date?
    }

    private var shownDays: Int {
        let available = VitalsPeriod.available(keeping: model.settings.historyRetention)
        return available.contains { $0.days == days } ? days : available.first { $0.days == 7 }?.days ?? available.last?.days ?? 7
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

    /// Days with any readings in them, for "a day" averages: a Mac that was off for a week shouldn't halve them.
    private func activeDays(_ report: VitalsReport) -> Int {
        guard shownDays > 1 else { return 1 }
        if report.granularity == .day { return max(report.periods.filter { !$0.charge.isEmpty }.count, 1) }
        return max(Int((report.whole.charge.total / (24 * 3600)).rounded(.up)), 1)
    }

    private func metrics(_ time: ChargeTime, report: VitalsReport) -> [MetricItem] {
        let days = activeDays(report)
        var metrics = [
            MetricItem(
                title: Text("Plugged In"), value: HistoryText.duration(time.pluggedIn / Double(days)), unit: days > 1 ? Text("a day") : nil,
                help: Text("\(HistoryText.duration(time.pluggedIn)) on the charger in all.")),
            MetricItem(
                title: Text("Reached Limit"), value: time.limitReached.formatted(), unit: Text(time.limitReached == 1 ? "time" : "times"),
                help: Text("How many times it finished charging, at its limit or full.")),
        ]
        if let held = time.heldPerArrival {
            metrics.append(
                MetricItem(
                    title: Text("Plugged In After"), value: HistoryText.duration(held), unit: Text("on average"), color: .teal,
                    help: Text("How long it stays on the charger once it's reached its limit, on average.")))
        }
        return metrics
    }

    private func careNotes(_ time: ChargeTime) -> [CareNote] {
        var notes: [CareNote] = []
        let limit = model.chargeLimit
        if time.full >= 2 * 3600 {
            if limit.isSupported, !limit.isLimited {
                notes.append(
                    CareNote(
                        symbol: "exclamationmark.triangle.fill", color: .orange,
                        title: String(localized: "Sat at 100% for \(HistoryText.duration(time.full))"),
                        detail: String(localized: "A battery wears fastest when it's kept full. A charge limit of 80% holds it lower while it's plugged in."),
                        action: .init(title: "Set a Charge Limit…") { model.settingsPane = .charging }))
            } else if !limit.isSupported {
                notes.append(
                    CareNote(
                        symbol: "exclamationmark.triangle.fill", color: .orange,
                        title: String(localized: "Sat at 100% for \(HistoryText.duration(time.full))"),
                        detail: String(
                            localized:
                                "A battery wears fastest when it's kept full. Optimized Battery Charging, in System Settings, holds it at 80% when it learns your routine."
                        ),
                        action: .init(title: "Open Battery Settings…") { model.openBatterySettings() }))
            } else {
                notes.append(
                    CareNote(
                        symbol: "bolt.badge.clock.fill", color: .orange,
                        title: String(localized: "Sat at 100% for \(HistoryText.duration(time.full))"),
                        detail: String(localized: "Charging to full once in a while is fine. If it's often, that was time the limit wasn't on.")))
            }
        }
        if time.holding >= 3600 {
            notes.append(
                CareNote(
                    symbol: "checkmark.shield.fill", color: .teal,
                    title: String(localized: "Spared \(HistoryText.duration(time.holding)) at full"),
                    detail: limit.isLimited
                        ? String(localized: "Your \(ChargingPane.percent(limit.limit)) charge limit held the battery below full while it was plugged in.")
                        : String(localized: "Optimized Battery Charging held the battery below full while it was plugged in.")))
        }
        if let held = time.heldPerArrival, held >= 6 * 3600, time.limitReached >= 2 {
            notes.append(
                CareNote(
                    symbol: "powerplug.fill", color: .gray,
                    title: String(localized: "Usually plugged in \(HistoryText.duration(held)) after charging"),
                    detail: limit.isLimited || time.full < time.holding
                        ? String(localized: "That's fine with a limit: the battery rests while the Mac runs from the charger.")
                        : String(localized: "Long stretches full are what a charge limit is for.")))
        }
        return notes
    }
}

/// The period's time as one bar, split by what the battery was doing, with what each part was.
private struct ChargeSplit: View {
    let time: ChargeTime

    var body: some View {
        let kinds = ChargeKind.allCases.filter { $0.seconds(time) > 0 }
        let total = max(time.total, 1)
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(kinds) { kind in
                        Rectangle()
                            .fill(kind.color.gradient)
                            .frame(width: max((proxy.size.width - Double(kinds.count - 1) * 2) * kind.seconds(time) / total, 3))
                            .help(Text("\(kind.title): \(HistoryText.duration(kind.seconds(time)))"))
                    }
                }
                .clipShape(.rect(cornerRadius: 5, style: .continuous))
            }
            .frame(height: 14)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 0) {
                ForEach(ChargeKind.allCases) { kind in
                    let seconds = kind.seconds(time)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(kind.color)
                                .frame(width: 7, height: 7)
                            Text(kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(HistoryText.duration(seconds))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(seconds > 0 ? .primary : .tertiary)
                            .contentTransition(.numericText())
                        Text(seconds > 0 ? HistoryText.share(seconds / total) : " ")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(kind.help)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(kind.title)
                    .accessibilityValue(DurationText.spoken(seconds))
                }
            }
        }
    }
}

/// Each day (or hour, or week) on the charger, stacked: charging, held at the limit, sitting full.
private struct ChargeTimeChart: View {
    let report: VitalsReport

    private static let kinds: [ChargeKind] = [.charging, .holding, .full]

    var body: some View {
        let periods = report.periods
        Chart {
            ForEach(periods) { period in
                ForEach(Self.kinds) { kind in
                    let hours = kind.seconds(period.charge) / 3600
                    if hours > 0 {
                        BarMark(
                            x: .value("Time", period.start, unit: unit), y: .value("Hours", hours), width: .ratio(periods.count > 45 ? 0.72 : 0.58)
                        )
                        .foregroundStyle(by: .value("Kind", kind.title))
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: Self.kinds.map(\.title), range: Self.kinds.map(\.color))
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: HistoryAxis.dates(periods.map(\.start), granularity: report.granularity)) { _ in
                AxisValueLabel(
                    format: HistoryAxis.format(count: periods.count, granularity: report.granularity),
                    centered: report.granularity != .hour && periods.count <= 14
                )
                .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(hours == 0 ? "0" : HistoryText.duration(hours * 3600))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time on the charger"))
        .accessibilityValue(Text("\(HistoryText.duration(report.whole.charge.pluggedIn)) in all."))
    }

    private var unit: Calendar.Component {
        switch report.granularity {
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        }
    }
}

/// Something about the period worth knowing, for the battery's sake.
private struct CareNote: Identifiable {
    struct Action {
        let title: LocalizedStringKey
        let perform: () -> Void
    }

    let symbol: String
    let color: Color
    let title: String
    let detail: String
    var action: Action?

    var id: String { title }

    init(symbol: String, color: Color, title: String, detail: String, action: Action? = nil) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.detail = detail
        self.action = action
    }
}

private struct CareNoteRow: View {
    let note: CareNote

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingIcon(symbol: note.symbol, color: note.color, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                Text(note.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action = note.action {
                Button(action.title, action: action.perform)
            }
        }
    }
}

/// The charge limit as it is, with the way to change it.
private struct ChargeLimitStatusRow: View {
    let model: AppModel

    var body: some View {
        let limit = model.chargeLimit
        LabeledContent {
            Button(limit.isSupported ? "Change…" : "Open…") {
                if limit.isSupported { model.settingsPane = .charging } else { model.openBatterySettings() }
            }
        } label: {
            SettingLabel("Charge Limit", symbol: limit.isLimited ? "battery.75percent" : "battery.100percent", color: .green) {
                if !limit.isSupported {
                    Text("Optimized Battery Charging is in System Settings › Battery.")
                } else if limit.isLimited {
                    Text("Charging stops at \(ChargingPane.percent(limit.limit)) while plugged in.")
                } else {
                    Text("Off: it charges all the way.")
                }
            }
        }
    }
}

/// Settings › Charging's way to the stats: the last week on the charger in a line.
struct ChargingStatsLink: View {
    let model: AppModel
    @State private var time: ChargeTime?

    var body: some View {
        LabeledContent {
            Button("Show Stats") { model.openSettings(.stats, tab: .charging) }
        } label: {
            SettingLabel("The Last 7 Days", symbol: "chart.bar.fill", color: .green) {
                if let time, !time.isEmpty {
                    Text(summary(time))
                } else {
                    Text("How long it's plugged in, held at its limit and sitting full.")
                }
            }
        }
        .task(id: model.history.vitalsRevision) {
            let now = Date()
            time = model.history.vitals.report(from: VitalsPeriod(days: 7).start(endingAt: now), to: now, granularity: .day).whole.charge
        }
    }

    private func summary(_ time: ChargeTime) -> String {
        var parts = [String(localized: "Plugged in \(HistoryText.duration(time.pluggedIn))")]
        if time.holding > 0 { parts.append(String(localized: "held at the limit \(HistoryText.duration(time.holding))")) }
        if time.full > 0 { parts.append(String(localized: "full \(HistoryText.duration(time.full))")) }
        return parts.joined(separator: " · ")
    }
}
