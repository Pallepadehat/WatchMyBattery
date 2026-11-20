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
        currentFlow()?.systemWatts
    }

    /// Where the power is going: what the whole Mac draws, and what it's actually getting from the charger.
    public func currentFlow() -> PowerFlow? {
        guard service != IO_OBJECT_NULL else { return nil }
        return Self.flow(
            telemetry: property("PowerTelemetryData") as? [String: Any],
            millivolts: property("Voltage") as? Int,
            milliamps: (property("InstantAmperage") ?? property("Amperage")) as? Int)
    }

    /// From the battery controller's properties. Separate so it can be tested with made-up ones.
    static func flow(telemetry: [String: Any]?, millivolts: Int?, milliamps: Int?) -> PowerFlow? {
        // Telemetry has the whole system's load, even on the adapter, when the battery itself sits idle, and what comes
        // in from the charger (milliwatts, both).
        if let telemetry, let load = telemetry["SystemLoad"] as? Int, load > 0 {
            let powerIn = (telemetry["SystemPowerIn"] as? Int).map { Double(max($0, 0)) / 1000 }
            return PowerFlow(systemWatts: Double(load) / 1000, chargerWatts: powerIn)
        }
        // Otherwise, what flows out of the battery: volts × amps (both reported in milli-units). Nothing's known about
        // the charger then.
        guard let millivolts, let milliamps, milliamps < 0 else { return nil }
        return PowerFlow(systemWatts: Double(millivolts) * Double(-milliamps) / 1_000_000, chargerWatts: nil)
    }

    private func property(_ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// The Mac's power at one moment.
public struct PowerFlow: Sendable, Equatable {
    /// What the whole Mac draws: display, chips, radios, everything.
    public var systemWatts: Double
    /// What it's getting from the charger right now (not what the charger is rated for); `nil` when the battery
    /// controller doesn't say. Zero on battery.
    public var chargerWatts: Double?

    public init(systemWatts: Double, chargerWatts: Double?) {
        self.systemWatts = systemWatts
        self.chargerWatts = chargerWatts
    }
}
