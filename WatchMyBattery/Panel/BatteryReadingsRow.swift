import BatteryKit
import SwiftUI

/// "Temperature  30 °C" and "Voltage & Current  12.41 V · 1.12 A out": the battery controller's readings, as two of
/// the panel's detail rows. Read every five seconds while the panel is open (they change slowly), and not at all
/// otherwise.
struct BatteryReadingsRows: View {
    let battery: BatteryMonitor
    /// The panel is on screen; reading stops when it isn't.
    let isVisible: Bool
    let usesColor: Bool
    let rowHeight: CGFloat

    var body: some View {
        let readings = battery.readings ?? BatteryReadings()
        Group {
            row("Temperature") {
                Text(temperature(readings))
                    .foregroundStyle(temperatureStyle(readings))
            }
            .help(temperatureHelp(readings))
            row("Voltage & Current") {
                Text(electrical(readings))
            }
            .help(electricalHelp(readings))
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled {
                battery.refreshReadings()
                try? await Task.sleep(for: .seconds(5), tolerance: .seconds(1))
            }
        }
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value()
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Temperature

    private func temperature(_ readings: BatteryReadings) -> String {
        guard let celsius = readings.temperature else { return "–" }
        return Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func temperatureStyle(_ readings: BatteryReadings) -> AnyShapeStyle {
        guard usesColor else { return AnyShapeStyle(.primary) }
        switch readings.warmth {
        case .hot: return AnyShapeStyle(.red)
        case .warm: return AnyShapeStyle(.orange)
        default: return AnyShapeStyle(.primary)
        }
    }

    private func temperatureHelp(_ readings: BatteryReadings) -> String {
        switch readings.warmth {
        case .hot: String(localized: "The battery is hot: macOS slows or pauses charging until it cools down.")
        case .warm: String(localized: "The battery is warm. Time spent warm wears it a little faster.")
        default: String(localized: "The battery's temperature.")
        }
    }

    // MARK: - Voltage and current

    /// "12.41 V · 1.12 A out", "· 2.30 A in" while charging, or just the volts when nothing flows.
    private func electrical(_ readings: BatteryReadings) -> String {
        guard let volts = readings.voltage else { return "–" }
        let voltage = volts.formatted(.number.precision(.fractionLength(2))) + " V"
        guard let amps = readings.current, abs(amps) >= 0.01 else { return voltage }
        let current = abs(amps).formatted(.number.precision(.fractionLength(2))) + " A"
        return amps > 0 ? String(localized: "\(voltage) · \(current) in") : String(localized: "\(voltage) · \(current) out")
    }

    private func electricalHelp(_ readings: BatteryReadings) -> String {
        guard let watts = readings.batteryWatts, abs(watts) >= 0.1 else {
            return String(localized: "What the battery controller measures right now.")
        }
        let formatted = abs(watts).formatted(.number.precision(.fractionLength(1)))
        return watts > 0
            ? String(localized: "\(formatted) W going into the battery.") : String(localized: "\(formatted) W coming out of the battery.")
    }
}
