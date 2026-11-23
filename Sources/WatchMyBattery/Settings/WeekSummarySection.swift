import BatteryKit
import SwiftUI

/// Settings › History's "Your Week": this week so far, or last week, against the week before. Time on battery, battery
/// used and the Mac's average draw, each with how it changed; the apps that used the most; the app that grew the most;
/// and the busiest day. What the Monday notification sums up, in full.
struct WeekSummarySection: View {
    let model: AppModel
    /// Click an app for its page.
    let open: (String) -> Void

    enum Week: Hashable { case thisWeek, lastWeek }

    @State private var week = Week.thisWeek
    @State private var summary: WeeklySummary?
    @State private var now = Date()

    var body: some View {
        Section {
            if let summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    MetricRow(metrics: metrics(summary))
                    if !summary.topApps.isEmpty {
                        TopApps(apps: summary.topApps, open: open)
                    }
                    let notes = notes(summary)
                    if !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(notes, id: \.text) { note in
                                Label(note.text, systemImage: note.symbol)
                                    .labelStyle(InlineIconLabelStyle(color: note.color))
                                    .font(.callout)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text(week == .thisWeek ? "This week's battery use shows here once the Mac has been on battery." : "Nothing on battery last week.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Picker("Week", selection: $week) {
                    Text("This Week").tag(Week.thisWeek)
                    Text("Last Week").tag(Week.lastWeek)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        } footer: {
            if let summary, summary.previous != nil {
                Text(summary.isUnderWay ? "Compared with the same days last week." : "Compared with the week before.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: Key(week: week, revision: model.history.revision, day: Calendar.current.startOfDay(for: now))) {
            let profile = model.history.profile
            summary =
                switch week {
                case .thisWeek: profile.weeklySummary(forWeekContaining: now, now: now)
                case .lastWeek: profile.lastWeekSummary(now: now)
                }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300), tolerance: .seconds(30))
                now = Date()
            }
        }
    }

    private struct Key: Equatable {
        let week: Week
        let revision: Int
        let day: Date
    }

    /// "Your Week · 9–15 Nov".
    private var title: String {
        guard let summary else { return String(localized: "Your Week") }
        let end = summary.interval.end.addingTimeInterval(-1)
        let range = (summary.interval.start..<max(end, summary.interval.start)).formatted(.interval.day().month(.abbreviated))
        return String(localized: "Your Week · \(range)")
    }

    private func metrics(_ summary: WeeklySummary) -> [MetricItem] {
        let previous = summary.previous
        return [
            MetricItem(
                title: Text("On Battery"), value: HistoryText.duration(summary.totals.batterySeconds),
                change: Self.change(summary.batteryTimeChange, higherIsWorse: nil)),
            MetricItem(
                title: Text("Battery Used"), value: HistoryText.points(Double(summary.totals.drained)),
                unit: summary.totals.charges >= 1
                    ? Text("· \(summary.totals.charges.formatted(.number.precision(.fractionLength(1)))) charges") : nil,
                change: Self.change(summary.drainedChange, higherIsWorse: nil)),
            MetricItem(
                title: Text("Average Draw"), value: summary.totals.averageWatts.map { $0.formatted(.number.precision(.fractionLength(1))) + " W" } ?? "–",
                help: previous?.averageWatts.map { Text("\($0.formatted(.number.precision(.fractionLength(1)))) W the week before.") },
                change: Self.change(summary.averageWattsChange, higherIsWorse: true)),
        ]
    }

    /// "↑20%": orange where more is worse, green where it's better, grey where it's neither (more time on battery is
    /// just more use).
    private static func change(_ value: Double?, higherIsWorse: Bool?) -> Text? {
        guard let value else { return nil }
        guard abs(value) >= 0.05 else { return Text("Same").foregroundStyle(.secondary) }
        let up = value > 0
        let color: Color =
            switch higherIsWorse.map({ $0 == up }) {
            case true?: .orange
            case false?: .green
            case nil: .secondary
            }
        let amount = abs(value).formatted(.percent.precision(.fractionLength(0)))
        return Text("\(Image(systemName: up ? "arrow.up" : "arrow.down"))\(amount)").foregroundStyle(color)
    }

    private struct Note {
        let text: String
        let symbol: String
        let color: Color
    }

    private func notes(_ summary: WeeklySummary) -> [Note] {
        var notes: [Note] = []
        if let rise = summary.biggestRise {
            notes.append(Note(text: WeeklySummaryText.rise(rise), symbol: "arrow.up.right.circle.fill", color: .orange))
        }
        if let busiest = summary.busiestDay, summary.interval.duration > 24 * 3600 {
            let day = busiest.start.formatted(.dateTime.weekday(.wide))
            notes.append(
                Note(
                    text: String(localized: "\(day) used the most: \(HistoryText.points(Double(busiest.drained)))."), symbol: "calendar.circle.fill",
                    color: .pink))
        }
        return notes
    }
}

/// The week's three hungriest apps, side by side, each with its share.
private struct TopApps: View {
    let apps: [UsageReport.App]
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(apps) { app in
                let look = AppLook.of(app.app)
                Button {
                    open(app.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: look.icon)
                            .resizable()
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.app.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text("\(HistoryText.share(app.share)) of apps' use")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(look.tint.opacity(0.12), in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Text("Open \(app.app.name)'s history"))
            }
        }
    }
}
