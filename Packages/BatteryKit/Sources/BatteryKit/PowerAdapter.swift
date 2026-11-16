import Foundation
import IOKit.ps

/// The charger the Mac is plugged into, as macOS describes it.
public struct PowerAdapter: Sendable, Equatable {
    /// What it can deliver, in watts, as agreed with the Mac when it was plugged in; `nil` when macOS doesn't say.
    public var watts: Int?
    /// Its name, when it gives one ("96W USB-C Power Adapter").
    public var name: String?

    public init(watts: Int?, name: String? = nil) {
        self.watts = watts
        self.name = name
    }
}

/// Reads the connected charger with `IOPSCopyExternalPowerAdapterDetails`: one call, no permission, and nothing
/// to watch, as the power source notifications already fire when a charger comes or goes.
public enum PowerAdapterReader {
    /// The charger, or `nil` on battery.
    public static func read() -> PowerAdapter? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
        return adapter(from: details)
    }

    /// From the details macOS hands over. Separate from `read()` so it can be tested with made-up ones.
    static func adapter(from details: [String: Any]) -> PowerAdapter? {
        // On battery, macOS still returns a dictionary, with only a family code of 0 in it.
        let watts = (details[kIOPSPowerAdapterWattsKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
        let name = (details[nameKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard watts != nil || name?.isEmpty == false else { return nil }
        return PowerAdapter(watts: watts, name: name?.isEmpty == false ? name : nil)
    }

    /// Apple's chargers have a name, under a key that isn't in the public headers.
    static let nameKey = "Name"
}
