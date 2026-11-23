import SwiftUI
import WidgetKit

/// WatchMyBattery's widgets, for the desktop and Notification Center, and its controls, for Control Center and the
/// menu bar (macOS 26 and later).
@main
struct WatchMyBatteryWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        AccessoriesWidget()
        if #available(macOS 26.0, *) {
            LowPowerModeControl()
            BatteryControl()
        }
    }
}
