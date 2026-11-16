import BatteryKit
import Foundation

extension MenuBarReadout {
    /// As the menu bar shows it: `84%`, `4:50` or `7.4 W`.
    var text: String {
        switch self {
        case .percentage(let percentage): (Double(percentage) / 100).formatted(.percent.precision(.fractionLength(0)))
        case .time(let interval): TimeFormat.clock(interval)
        case .watts(let watts): PowerFormat.watts(watts)
        }
    }
}
