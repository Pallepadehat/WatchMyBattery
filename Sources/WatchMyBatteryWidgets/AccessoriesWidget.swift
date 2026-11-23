import BatteryKit
import SwiftUI
import WidgetKit

/// The Mac and its accessories, a ring each, like iPhone's Batteries widget: AirPods, Magic Mouse, Keyboard and
/// Trackpad, and an iPhone or iPad when WatchMyBattery can read it.
struct AccessoriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Accessories", provider: BatteryProvider()) { entry in
            AccessoriesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "watchmybattery://panel"))
        }
        .configurationDisplayName("Batteries")
        .description("Your Mac, AirPods and Magic accessories, each with its battery.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct Device: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let level: Int
    let isCharging: Bool

    /// The name without what goes without saying under a ring: "Apple Magic Keyboard" is "Magic Keyboard", and
    /// "Patrick's iPhone" is "iPhone".
    var shortName: String {
        var short = name
        if short.hasPrefix("Apple ") { short.removeFirst(6) }
        if let owner = short.range(of: #"^\S+['’]s "#, options: .regularExpression) { short.removeSubrange(owner) }
        return short.isEmpty ? name : short
    }
}

struct AccessoriesWidgetView: View {
    let entry: BatteryEntry
    /// Set to draw a size outside WidgetKit (the preview renderer); otherwise the widget's own.
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    private var devices: [Device] {
        var devices: [Device] = []
        if let battery = entry.battery {
            devices.append(
                Device(id: "mac", name: String(localized: "This Mac"), symbol: "laptopcomputer", level: battery.percentage, isCharging: battery.isPluggedIn))
        }
        for accessory in entry.state?.accessories ?? [] {
            // Earbuds show the earbuds (the lower, when they differ); the case only when they're all there is.
            let parts = accessory.parts.filter { $0.role != "case" }
            let shown = parts.min { $0.percentage < $1.percentage } ?? accessory.parts.first
            guard let shown else { continue }
            devices.append(Device(id: accessory.id, name: accessory.name, symbol: accessory.symbol, level: shown.percentage, isCharging: shown.isCharging))
        }
        return devices
    }

    var body: some View {
        let devices = devices
        if devices.count <= 1, entry.state == nil {
            VStack(alignment: .leading, spacing: 6) {
                if let mac = devices.first { DeviceRing(device: mac, diameter: 56) }
                OpenAppHint()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if family == .systemSmall {
            small(Array(devices.prefix(4)))
        } else {
            medium(Array(devices.prefix(4)))
        }
    }

    /// One big ring, two side by side, or a grid of three or four: each as large as the room allows, none left empty.
    @ViewBuilder private func small(_ devices: [Device]) -> some View {
        switch devices.count {
        case 0:
            EmptyView()
        case 1:
            VStack(spacing: 8) {
                DeviceRing(device: devices[0], diameter: 88)
                DeviceName(device: devices[0], size: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case 2:
            HStack(alignment: .top, spacing: 10) {
                ForEach(devices) { device in
                    VStack(spacing: 7) {
                        DeviceRing(device: device, diameter: 60)
                        DeviceName(device: device, size: 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        default:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(devices.prefix(2)) { DeviceRing(device: $0, diameter: 58) }
                }
                HStack(spacing: 12) {
                    ForEach(devices.dropFirst(2)) { DeviceRing(device: $0, diameter: 58) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One device large with its name beside it; otherwise a column each, spread across the width.
    @ViewBuilder private func medium(_ devices: [Device]) -> some View {
        if devices.count == 1, let device = devices.first {
            HStack(spacing: 18) {
                DeviceRing(device: device, diameter: 104)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text(device.isCharging ? String(localized: "Charging") : String(localized: "On battery"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        } else {
            let diameter: CGFloat = devices.count == 2 ? 76 : devices.count == 3 ? 70 : 64
            HStack(alignment: .top, spacing: 4) {
                ForEach(devices) { device in
                    VStack(spacing: 8) {
                        DeviceRing(device: device, diameter: diameter)
                        DeviceName(device: device, size: devices.count == 4 ? 10 : 11)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// A device's ring: its symbol and percentage inside, everything sized from the ring's diameter so any size looks
/// the same.
private struct DeviceRing: View {
    let device: Device
    let diameter: CGFloat

    var body: some View {
        let color = WidgetColors.of(level: device.level, isCharging: device.isCharging)
        let lineWidth = (diameter * 0.095).rounded()
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(Double(device.level) / 100, 0.01))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: diameter * 0.03) {
                Image(systemName: device.symbol)
                    .font(.system(size: diameter * 0.2, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: diameter * 0.22)
                HStack(spacing: 1) {
                    if device.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: diameter * 0.13, weight: .bold))
                            .foregroundStyle(color)
                    }
                    Text(WidgetText.percent(device.level))
                        .font(.system(size: diameter * 0.19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(lineWidth * 1.4)
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name), \(WidgetText.percent(device.level))")
    }
}

/// A device's name under its ring: the same size for all, centred, on up to two lines rather than shrunk.
private struct DeviceName: View {
    let device: Device
    let size: CGFloat

    var body: some View {
        Text(device.shortName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}
