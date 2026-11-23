import AppIntents
import BatteryKit
import SwiftUI
import WidgetKit

// MARK: - Controls

/// Low Power Mode, as a toggle for Control Center or the menu bar.
@available(macOS 26.0, *)
struct LowPowerModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LowPowerMode", provider: LowPowerModeValue()) { isOn in
            ControlWidgetToggle("Low Power Mode", isOn: isOn, action: WidgetSetLowPowerModeIntent()) { on in
                Label(on ? "On" : "Off", systemImage: "leaf.fill")
            }
            .tint(.yellow)
        }
        .displayName("Low Power Mode")
        .description("Turns Low Power Mode on or off, through WatchMyBattery.")
    }
}

@available(macOS 26.0, *)
struct LowPowerModeValue: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

/// The battery's level and time left, as a button that opens the panel.
@available(macOS 26.0, *)
struct BatteryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Battery", provider: BatteryValue()) { battery in
            ControlWidgetButton(action: OpenPanelIntent()) {
                Label {
                    Text(battery.map { WidgetText.percent($0.percentage) } ?? "–")
                    if let battery { Text(WidgetText.status(battery)) }
                } icon: {
                    Image(systemName: Self.symbol(battery))
                }
            }
            .tint(battery.map(WidgetColors.of) ?? .green)
        }
        .displayName("Battery")
        .description("Your battery's level and time left. Click it for WatchMyBattery's panel.")
    }

    static func symbol(_ battery: WidgetState.Battery?) -> String {
        guard let battery else { return "battery.100percent" }
        if battery.isPluggedIn { return "battery.100percent.bolt" }
        switch battery.percentage {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

@available(macOS 26.0, *)
struct BatteryValue: ControlValueProvider {
    var previewValue: WidgetState.Battery? {
        .init(percentage: 72, isPluggedIn: false, isCharging: false, isLowPowerModeOn: false, timeRemaining: 4 * 3600, chargeTarget: 100)
    }

    func currentValue() async throws -> WidgetState.Battery? {
        let snapshot = PowerSourceReader.read()
        return snapshot.hasBattery ? WidgetState.Battery(snapshot) : nil
    }
}
