import Foundation
import IOKit

/// Reads how much power the whole Mac is drawing right now, in watts, from
/// the battery controller (the `AppleSmartBattery` IORegistry entry).
public final class SystemPowerReader: @unchecked Sendable {
    // An io_service_t is just a handle; IOKit's registry calls are thread-safe.
    private let service: io_service_t

    public init() {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    deinit {
        if service != IO_OBJECT_NULL { IOObjectRelease(service) }
    }

    /// The system's power draw in watts, or `nil` when it isn't available
    /// (no battery, or an unusual battery controller).
    public func currentWatts() -> Double? {
        guard service != IO_OBJECT_NULL else { return nil }
        // Telemetry has the whole system's load, even on the adapter, when the battery itself sits idle.
        if let telemetry = property("PowerTelemetryData") as? [String: Any],
            let load = telemetry["SystemLoad"] as? Int, load > 0
        {
            return Double(load) / 1000
        }
        // Otherwise, what flows out of the battery: volts × amps (both reported in milli-units).
        guard let millivolts = property("Voltage") as? Int,
            let milliamps = (property("InstantAmperage") ?? property("Amperage")) as? Int,
            milliamps < 0
        else { return nil }
        return Double(millivolts) * Double(-milliamps) / 1_000_000
    }

    private func property(_ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
