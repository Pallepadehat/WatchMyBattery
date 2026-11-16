import BatteryKit
import Foundation
import Observation

/// The whole Mac's power draw, for the menu bar's "Power Draw" text.
///
/// The one reading that has to be polled: macOS doesn't announce it. So it's read only while the menu bar shows it
/// and someone could see it (the owner turns it off while the displays sleep), every few seconds with slack for macOS
/// to group the wake-ups, and it publishes only when the rounded number in the menu bar would change. A reading is a
/// single registry property, a fraction of a millisecond.
@Observable
final class PowerDrawMonitor {
    /// Smoothed, in watts; `nil` until the first reading, or on a Mac that doesn't report it.
    private(set) var watts: Double?

    @ObservationIgnored private let reader = SystemPowerReader()
    @ObservationIgnored private var smoother = SingleValueSmoother(responsiveness: 0.5)
    @ObservationIgnored private var task: Task<Void, Never>?

    static let interval: Duration = .seconds(3)

    /// Reads while `wanted`, and stops (forgetting the last reading, which would be stale) when it isn't.
    func setActive(_ wanted: Bool) {
        if wanted {
            guard task == nil else { return }
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.read()
                    try? await Task.sleep(for: Self.interval, tolerance: .seconds(1))
                }
            }
        } else {
            task?.cancel()
            task = nil
            smoother.reset()
            if watts != nil { watts = nil }
        }
    }

    private func read() {
        guard let reading = reader.currentWatts() else { return }
        smoother.add(reading)
        guard let next = smoother.value else { return }
        // Only a change the menu bar would show.
        if watts.map({ PowerFormat.watts($0) != PowerFormat.watts(next) }) ?? true { watts = next }
    }
}
