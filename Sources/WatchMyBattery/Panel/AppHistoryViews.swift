import BatteryKit
import Charts
import SwiftUI

// The pieces an app's history is shown with, in the panel and in Settings › History.

/// The words and numbers the history uses, the same everywhere.
enum HistoryText {
    /// "2h 10m", "45m", "412h": time on battery, however long.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return Duration.seconds(0).formatted(.units(allowed: [.minutes], width: .narrow)) }
        // Past a hundred hours, the minutes are noise.
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 100 * 3600 ? [.hours] : [.hours, .minutes]
        return Duration.seconds((seconds / 60).rounded() * 60).formatted(.units(allowed: units, width: .narrow, maximumUnitCount: 2))
    }

    /// The battery time an app cost: "42m", "1h 10m", or "under 1m", which would otherwise round away to nothing.
    static func cost(_ time: TimeInterval?) -> String? {
        guard let time else { return nil }
        return time < 60 ? String(localized: "under 1m") : duration(time)
    }

    /// "18%", or "<1%" for a sliver.
    static func share(_ fraction: Double) -> String {
        guard fraction >= 0.005 else { return "<" + (0.01).formatted(.percent.precision(.fractionLength(0))) }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "34%": percentage points of the battery.
    static func points(_ points: Double) -> String {
        (points / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "14:00" or "2:00 PM", as the Mac shows times.
    static func hourOfDay(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "09" or "9 AM": an hour on a chart's axis, as short as the Mac's clock allows.
    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    /// "1.2 W", or "<0.1 W".
    static func watts(_ watts: Double) -> String { AppDetailCard.watts(watts) }

    /// "Up 23%", "Down 15%" or "About the same": a change under a tenth either way is noise.
    static func change(_ change: Double) -> String {
        let amount = abs(change).formatted(.percent.precision(.fractionLength(0)))
        if change >= 0.1 { return String(localized: "Up \(amount)") }
        if change <= -0.1 { return String(localized: "Down \(amount)") }
        return String(localized: "About the same")
    }

    /// The panel's one short line about an app: "67% of app use · peaks around 19:00".
    static func peekFacts(_ report: AppUsageReport) -> String {
        var facts = [String(localized: "\(share(report.share)) of app use")]
        if let hour = report.busiestHour {
            facts.append(String(localized: "peaks around \(hourOfDay(hour))"))
        } else if report.granularity != .hour, report.dayCount > 1 {
            facts.append(String(localized: "\(report.activeDays) of \(report.dayCount) days"))
        }
        return facts.joined(separator: " · ")
    }
}

/// An app's use over the report's periods, a bar each, in the app's colour. Bars show battery time when the Mac's
/// power draw is known, energy otherwise; only their heights matter, so the compact one has no axis.
struct AppUsageBars: View {
    let report: AppUsageReport
    let tint: Color
    var height: CGFloat = 40
    var showsAxes = false
    /// A period picked by clicking its bar; `nil` when the bars can't be picked.
    var selection: Binding<Date?>?

    var body: some View {
        let periods = report.periods
        let top = periods.map(value).max() ?? 0
        Chart {
            ForEach(periods) { period in
                BarMark(
                    x: .value("Time", period.start, unit: unit),
                    y: .value("Used", value(period)),
                    width: .ratio(report.granularity == .hour ? 0.7 : 0.58)
                )
                .cornerRadius(showsAxes ? 3 : 1.5)
                .foregroundStyle(color(for: period))
            }
            // Always there, faded while a bar is picked: taking it (and its label) away would resize the plot and
            // shift every bar sideways.
            if showsAxes, let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(selection?.wrappedValue == nil ? 1 : 0.35))
            }
        }
        .chartYScale(domain: 0...max(top, 0.000_1))
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: HistoryAxis.dates(periods.map(\.start), granularity: report.granularity)) { _ in
                    AxisValueLabel(
                        format: HistoryAxis.format(count: periods.count, granularity: report.granularity),
                        centered: report.granularity != .hour && periods.count <= 14
                    )
                    .foregroundStyle(Color.secondary)
                }
            } else if report.granularity == .hour {
                // Even in the compact chart, a few hours say when the bars are.
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour(), collisionResolution: .greedy)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }
            } else {
                AxisMarks(values: periods.map(\.start)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(axisLabel(amount))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            if showsAxes, let average {
                AxisMarks(position: .leading, values: [average]) { _ in
                    AxisValueLabel {
                        Text("avg")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis(showsAxes ? .automatic : .hidden)
        .modifier(PeriodPicking(periods: periods.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }, selection: selection))
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(report.app.name), battery used over time"))
        .accessibilityValue(accessibilitySummary)
    }

    /// Over the periods it used anything in.
    private var average: Double? {
        let used = report.periods.map(value).filter { $0 > 0 }
        guard used.count >= 2 else { return nil }
        return used.reduce(0, +) / Double(used.count)
    }

    /// Battery time in minutes when it's known, watt-hours otherwise.
    private var usesTime: Bool { report.periods.contains { $0.batteryTime != nil } }

    private func value(_ period: AppUsageReport.Period) -> Double {
        usesTime ? (period.batteryTime ?? 0) / 60 : period.joules / 3600
    }

    private func axisLabel(_ amount: Double) -> String {
        if amount == 0 { return usesTime ? "0" : "0 Wh" }
        return usesTime ? HistoryText.duration(amount * 60) : amount.formatted(.number.precision(.significantDigits(2))) + " Wh"
    }

    private func color(for period: AppUsageReport.Period) -> Color {
        guard let selected = selection?.wrappedValue else { return tint }
        return period.start == selected ? tint : tint.opacity(0.25)
    }

    private var unit: Calendar.Component {
        switch report.granularity {
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        }
    }

    private var accessibilitySummary: String {
        guard let busiest = report.periods.max(by: { $0.joules < $1.joules }), busiest.joules > 0 else {
            return String(localized: "Nothing used yet.")
        }
        let when =
            report.granularity == .hour
            ? busiest.start.formatted(date: .omitted, time: .shortened) : busiest.start.formatted(.dateTime.weekday(.wide).day().month())
        return String(localized: "Used the most at \(when).")
    }
}

/// Clicking a bar picks its period, and clicking it again lets go; the arrow keys step through them for VoiceOver.
struct PeriodPicking: ViewModifier {
    let periods: [DateInterval]
    let selection: Binding<Date?>?

    func body(content: Content) -> some View {
        if let selection, !periods.isEmpty {
            content
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(.rect)
                            .onTapGesture { location in
                                guard let frame = proxy.plotFrame else { return }
                                let x = location.x - geometry[frame].origin.x
                                guard let date: Date = proxy.value(atX: x),
                                    let period = periods.first(where: { $0.start <= date && date < $0.end })
                                else { return }
                                withAnimation(.snappy(duration: 0.25)) {
                                    selection.wrappedValue = selection.wrappedValue == period.start ? nil : period.start
                                }
                            }
                    }
                }
                .accessibilityAdjustableAction { direction in
                    let index = periods.firstIndex { $0.start == selection.wrappedValue }
                    switch direction {
                    case .increment: selection.wrappedValue = periods[min((index ?? -1) + 1, periods.count - 1)].start
                    case .decrement: selection.wrappedValue = index.map { $0 > 0 ? periods[$0 - 1].start : nil } ?? nil
                    @unknown default: break
                    }
                }
        } else {
            content
        }
    }
}

/// Where the date labels go on the history's charts: every day for a week or two, then every week or two, or the
/// first week of each month over a year, so they never crowd.
enum HistoryAxis {
    static func dates(_ starts: [Date], granularity: UsageReport.Granularity) -> [Date] {
        switch granularity {
        case .hour: return starts.filter { Calendar.current.component(.hour, from: $0) % 6 == 0 }
        case .week: return starts.filter { Calendar.current.component(.day, from: $0) <= 7 }
        case .day:
            guard starts.count > 14 else { return starts }
            let step = starts.count > 45 ? 14 : 7
            return starts.enumerated().filter { (starts.count - 1 - $0.offset) % step == 0 }.map(\.element)
        }
    }

    static func format(count: Int, granularity: UsageReport.Granularity) -> Date.FormatStyle {
        switch granularity {
        case .hour: .dateTime.hour()
        case .week: .dateTime.month(.abbreviated)
        case .day: count > 14 ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.abbreviated)
        }
    }
}
