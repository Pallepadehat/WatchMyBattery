import AppIntents
import BatteryKit
import Charts
import SwiftUI
import WidgetKit

// The pieces the widgets are drawn with.

enum WidgetColors {
    static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let red = Color(red: 0.95, green: 0.27, blue: 0.23)
    static let yellow = Color(red: 1, green: 0.8, blue: 0.0)
    static let lowLevel = 20

    /// Green while charging, yellow in Low Power Mode, red when low, as in the menu bar.
    static func of(_ battery: WidgetState.Battery) -> Color {
        if battery.isPluggedIn { return green }
        if battery.isLowPowerModeOn { return yellow }
        if battery.percentage <= lowLevel { return red }
        return green
    }

    static func of(level: Int, isCharging: Bool) -> Color {
        if isCharging { return green }
        return level <= lowLevel ? red : green
    }
}

enum WidgetText {
    static func percent(_ level: Int) -> String {
        (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "4:35 left", "1:05 to full", "Charged", "Not Charging".
    static func status(_ battery: WidgetState.Battery) -> String {
        if battery.isPluggedIn {
            if battery.isCharging {
                return battery.timeRemaining.map { String(localized: "\(TimeFormat.clock($0)) to full") } ?? String(localized: "Charging")
            }
            if battery.chargeTarget < 100, battery.percentage >= battery.chargeTarget - 2 {
                return String(localized: "Held at \(percent(battery.chargeTarget))")
            }
            return battery.percentage >= battery.chargeTarget ? String(localized: "Charged") : String(localized: "Not Charging")
        }
        return battery.timeRemaining.map { String(localized: "\(TimeFormat.clock($0)) left") } ?? String(localized: "On Battery")
    }

    /// "16:40", or "Tue 08:10" past today.
    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// A ring that fills with the level, with the percentage in the middle and a bolt while plugged in.
struct LevelRing: View {
    let level: Int
    let color: Color
    var isPluggedIn = false
    var lineWidth: CGFloat = 7
    var symbol: String?
    var showsPercentage = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(Double(level) / 100, 0.01))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: 0) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if showsPercentage {
                    HStack(spacing: 1) {
                        if isPluggedIn {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(color)
                        }
                        Text(WidgetText.percent(level))
                            .font(.system(size: symbol == nil ? 22 : 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }
                }
            }
            .padding(lineWidth)
        }
        .padding(lineWidth / 2)
    }
}

/// An app among the hungriest: icon, name, a bar for its share, and the battery time it cost.
struct AppRow: View {
    let app: WidgetState.App
    let icon: NSImage?
    let largest: Double

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().keepsColor()
                } else {
                    Image(systemName: "app.fill").resizable().foregroundStyle(.tertiary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(app.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(app.share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint)
                                .frame(width: proxy.size.width * (largest > 0 ? app.share / largest : 0))
                                .widgetAccentable()
                        }
                }
                .frame(height: 4)
            }
        }
    }

    /// The slice's colour from the panel, or grey.
    private var tint: Color {
        guard let rgb = app.tint, rgb.count == 3 else { return Color.secondary.opacity(0.7) }
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}

/// The last 24 hours (18 with a forecast) as bars, and where the level's headed as a dashed line.
struct LevelHistoryChart: View {
    let levels: [WidgetState.Level]
    let forecast: WidgetState.Forecast?
    let now: Date

    var body: some View {
        let ahead: TimeInterval = forecast == nil ? 0 : 6 * 3600
        let start = now.addingTimeInterval(-24 * 3600 + ahead)
        let end = now.addingTimeInterval(ahead)
        let shown = levels.filter { $0.start >= start }
        let line = (forecast?.points ?? []).filter { $0.date <= end }
        Chart {
            ForEach(shown, id: \.start) { level in
                RectangleMark(
                    xStart: .value("Start", level.start.addingTimeInterval(240)), xEnd: .value("End", level.start.addingTimeInterval(1560)),
                    yStart: .value("Empty", 0), yEnd: .value("Level", level.percentage)
                )
                .foregroundStyle(
                    level.isPluggedIn ? WidgetColors.green : (level.percentage <= WidgetColors.lowLevel ? WidgetColors.red : Color.secondary.opacity(0.55))
                )
                .cornerRadius(1)
            }
            if !line.isEmpty {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(line, id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Expected", point.percentage))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
                        .foregroundStyle(lineColor(line))
                }
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let level = value.as(Int.self) {
                        Text(WidgetText.percent(level)).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            // Every six hours, but not right at the edges, where the label would be cut off.
            AxisMarks(values: hourMarks(from: start, to: end)) { _ in
                AxisValueLabel(format: .dateTime.hour()).font(.system(size: 8)).foregroundStyle(Color.secondary)
            }
        }
    }
}

extension LevelHistoryChart {
    fileprivate func hourMarks(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        var marks: [Date] = []
        var date = calendar.dateInterval(of: .hour, for: start)?.end ?? start
        while date < end.addingTimeInterval(-2 * 3600) {
            if calendar.component(.hour, from: date) % 6 == 0, date > start.addingTimeInterval(1800) { marks.append(date) }
            date = date.addingTimeInterval(3600)
        }
        return marks
    }

    /// Grey, or red when the line ends up low.
    fileprivate func lineColor(_ line: [WidgetState.Forecast.Point]) -> Color {
        (line.last?.percentage ?? 100) <= Double(WidgetColors.lowLevel) ? WidgetColors.red : Color.secondary
    }
}

/// "Low Power Mode", in yellow: shown only while it's on, as a state rather than a switch.
struct LowPowerModeBadge: View {
    var body: some View {
        Label("Low Power", systemImage: "leaf.fill")
            .font(.system(size: 10, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(WidgetColors.yellow, in: .capsule)
            .widgetAccentable()
            .accessibilityLabel("Low Power Mode is on")
    }
}

/// When the app's never written its state (it isn't running), what to say instead of apps.
struct OpenAppHint: View {
    var body: some View {
        Text("Open WatchMyBattery to see the apps using the most battery.")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }
}

extension Image {
    /// Keeps an app's icon in colour when macOS shows the widget tinted or monochrome (on the desktop behind windows,
    /// say), where every image is otherwise drawn as a solid silhouette: a rounded white square, for an app icon.
    @ViewBuilder func keepsColor() -> some View {
        if #available(macOS 15.0, *) {
            self.widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}
