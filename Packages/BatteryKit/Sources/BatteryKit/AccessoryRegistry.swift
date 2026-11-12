import Foundation
import IOKit

/// The devices in the IORegistry that report a `BatteryPercent`: the Magic
/// Mouse, Keyboard and Trackpad.
///
/// They're found by that property rather than by their registry class, the
/// way `ioreg -r -k BatteryPercent` finds them, so a macOS update that
/// moves them to another class doesn't lose them. Searching the whole
/// registry like that takes a few milliseconds, so it's done only now and
/// then (``rescan()``: at launch, after waking, and when a device comes or
/// goes). In between, ``entries()`` reads the devices found last time
/// directly, which takes microseconds.
public final class AccessoryRegistry {
    private var services: [io_service_t] = []

    public init() {}

    deinit {
        for service in services { IOObjectRelease(service) }
    }

    /// Where Magic accessories are in the registry on current macOS versions.
    static let knownClass = "AppleDeviceManagementHIDEventService"

    /// A matching dictionary for every service with a `BatteryPercent`, for searching and for notifications.
    static func matching() -> CFMutableDictionary {
        let matching = IOServiceMatching("IOService") as NSMutableDictionary
        matching[kIOPropertyExistsMatchKey] = AccessoryReader.registryBatteryKey
        return matching
    }

    /// Searches the registry again.
    public func rescan() {
        for service in services { IOObjectRelease(service) }
        services = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, Self.matching(), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        // The iterator hands over a reference to each service, which is kept until the next search.
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL { services.append(service) }
    }

    /// The properties of the devices found by the last search. A device that has since gone reports nothing and is left out.
    public func entries() -> [[String: Any]] {
        services.compactMap { service in
            var entry: [String: Any] = [:]
            // Only the few properties needed, rather than copying every property of the device.
            for key in AccessoryReader.registryKeys {
                if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    entry[key] = value
                }
            }
            return entry[AccessoryReader.registryBatteryKey] == nil ? nil : entry
        }
    }

    /// A search and a read at once, for a one-off reading (Shortcuts, tests).
    public static func scanOnce() -> [[String: Any]] {
        let registry = AccessoryRegistry()
        registry.rescan()
        return registry.entries()
    }
}
