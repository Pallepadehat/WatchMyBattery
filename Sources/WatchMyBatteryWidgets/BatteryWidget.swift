import BatteryKit
import SwiftUI
import WidgetKit

/// The battery at a glance: its level and time left, the apps that used the most of it, and in the large size its last
/// day with the forecast. Click it for the panel.
struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Battery", provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "watchmybattery://panel"))
        }
        .configurationDisplayName("Battery")
        .description("Your battery's level and time left, the apps using it the most, and where it's headed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BatteryWidgetView: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let battery = entry.battery {
            switch family {
            case .systemSmall: SmallBattery(entry: entry, battery: battery)
            case .systemLarge: LargeBattery(entry: entry, battery: battery)
            default: MediumBattery(entry: entry, battery: battery)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "powerplug.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("This Mac doesn't have a battery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// The ring, the time left, and when it reaches 20%.
struct SmallBattery: View {
    let entry: BatteryEntry
    let battery: WidgetState.Battery

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LevelRing(level: battery.percentage, color: WidgetColors.of(battery), isPluggedIn: battery.isPluggedIn, lineWidth: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 1) {
                Text(WidgetText.status(battery))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var detail: String {
        if !battery.isPluggedIn, let low = entry.state?.forecast?.reachesLow, low > entry.date {
            return String(localized: "\(WidgetText.percent(WidgetColors.lowLevel)) around \(WidgetText.time(low))")
        }
        if battery.isLowPowerModeOn { return String(localized: "Low Power Mode") }
        if let used = entry.state?.usedToday, used > 0 { return String(localized: "\(WidgetText.percent(used)) used today") }
        return battery.isPluggedIn ? String(localized: "Plugged in") : String(localized: "On battery")
    }
}

/// The ring and its numbers on the left, the hungriest apps on the right.
struct MediumBattery: View {
    let entry: BatteryEntry
    let battery: WidgetState.Battery

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                LevelRing(level: battery.percentage, color: WidgetColors.of(battery), isPluggedIn: battery.isPluggedIn, lineWidth: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(WidgetText.status(battery))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                if battery.isLowPowerModeOn {
                    LowPowerModeBadge()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 104)

            VStack(alignment: .leading, spacing: 7) {
                Text("Used the most")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let apps = entry.state?.apps, !apps.isEmpty {
                    let largest = apps.map(\.share).max() ?? 1
                    ForEach(apps.prefix(3)) { app in
                        AppRow(app: app, icon: entry.icon(for: app), largest: largest)
                    }
                } else if entry.state == nil {
                    OpenAppHint()
                } else {
                    Text("Apps show up here once they've been measured on battery.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let line = forecastLine {
                    Label(line, systemImage: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var forecastLine: String? {
        guard !battery.isPluggedIn, let low = entry.state?.forecast?.reachesLow, low > entry.date else { return nil }
        return String(localized: "\(WidgetText.percent(WidgetColors.lowLevel)) around \(WidgetText.time(low))")
    }
}

/// The ring and numbers, the last day with the forecast, and the apps.
struct LargeBattery: View {
    let entry: BatteryEntry
    let battery: WidgetState.Battery

    var body: some View {
        // 344 points square on macOS, so everything is sized to fit, and the chart takes whatever room is left.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                LevelRing(level: battery.percentage, color: WidgetColors.of(battery), isPluggedIn: battery.isPluggedIn, lineWidth: 6)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetText.status(battery))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    ForEach(details, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
                if battery.isLowPowerModeOn {
                    LowPowerModeBadge()
                }
            }

            if let levels = entry.state?.levels, !levels.isEmpty {
                LevelHistoryChart(levels: levels, forecast: battery.isPluggedIn ? nil : entry.state?.forecast, now: entry.date)
                    .frame(minHeight: 60, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Used the most, last 24 hours")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let apps = entry.state?.apps, !apps.isEmpty {
                    let largest = apps.map(\.share).max() ?? 1
                    ForEach(apps.prefix(4)) { app in
                        AppRow(app: app, icon: entry.icon(for: app), largest: largest)
                    }
                } else if entry.state == nil {
                    OpenAppHint()
                } else {
                    Text("Apps show up here once they've been measured on battery.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Under the status: plugged in, or when it should reach 20%, and what today used.
    private var details: [String] {
        var lines: [String] = []
        if battery.isPluggedIn {
            lines.append(String(localized: "Plugged in"))
        } else if let low = entry.state?.forecast?.reachesLow, low > entry.date {
            lines.append(String(localized: "\(WidgetText.percent(WidgetColors.lowLevel)) around \(WidgetText.time(low))"))
        }
        if let used = entry.state?.usedToday, used > 0 {
            lines.append(String(localized: "\(WidgetText.percent(used)) used today"))
        }
        return lines
    }
}
