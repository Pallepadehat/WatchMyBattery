import Foundation
import IOKit
import IOKit.ps

/// Reads the batteries of connected Bluetooth accessories.
///
/// macOS has no public API for this, so it reads the same two places the
/// system's own Bluetooth menu and `pmset -g accps` do:
///
/// - **IOPowerSources' accessory list**, where AirPods, Beats and other
///   headphones (and, on recent macOS versions, most other accessories) are
///   published, with each earbud and the case as separate batteries. The
///   list is read with `IOPSCopyPowerSourcesByType`, which IOKit exports but
///   doesn't declare in its headers, so it's looked up at runtime: if a
///   future macOS removes it, accessories simply don't show up.
/// - **The HID registry**, where the Magic Mouse, Keyboard and Trackpad keep
///   a `BatteryPercent` property.
///
/// Neither needs Bluetooth permission, and a read takes well under a millisecond.
public enum AccessoryReader {
    public static func read() -> [Accessory] {
        merge(powerSources: accessories(fromPowerSources: readPowerSources()), registry: accessories(fromRegistry: readRegistry()))
    }

    // MARK: - IOPowerSources

    /// Turns IOPowerSources accessory descriptions into accessories, joining
    /// the parts that belong together (two earbuds and their case).
    public static func accessories(fromPowerSources descriptions: [[String: Any]]) -> [Accessory] {
        // The order they were first seen in, so the result doesn't shuffle around.
        var order: [String] = []
        var groups: [String: [[String: Any]]] = [:]
        for description in descriptions {
            guard description[kIOPSTypeKey] as? String == Key.accessoryType,
                description[kIOPSIsPresentKey] as? Bool ?? true
            else { continue }
            guard
                let group = description[Key.groupIdentifier] as? String ?? description[Key.accessoryIdentifier] as? String
                    ?? description[kIOPSNameKey] as? String
            else { continue }
            if groups[group] == nil { order.append(group) }
            groups[group, default: []].append(description)
        }
        return order.compactMap { id in groups[id].flatMap { accessory(id: id, descriptions: $0) } }
    }

    private static func accessory(id: String, descriptions: [[String: Any]]) -> Accessory? {
        var parts: [Accessory.Part.Role: Accessory.Part] = [:]
        var names: [String] = []
        var caseName: String?
        var categories: [String] = []
        var productID: Int?
        var vendorID: Int?

        for description in descriptions {
            let name = description[kIOPSNameKey] as? String
            let category = description[Key.category] as? String
            if let category { categories.append(category) }
            productID = productID ?? description[Key.productID] as? Int
            vendorID = vendorID ?? description[Key.vendorID] as? Int

            // Earbuds come as one "Combined" battery with each earbud inside it.
            let combined = description[Key.combinedParts] as? [[String: Any]] ?? []
            let pieces = combined.isEmpty ? [description] : combined
            for piece in pieces {
                let role = role(of: piece)
                guard let part = part(from: piece, role: role) else { continue }
                parts[role] = part
            }
            if let name {
                if role(of: description) == .case { caseName = name } else { names.append(name) }
            }
        }

        guard !parts.isEmpty else { return nil }
        // The case is often published alone for a moment, before the earbuds connect.
        let name = names.first ?? caseName.map(withoutCaseSuffix) ?? ""
        let kind = kind(categories: categories, name: name, roles: Set(parts.keys))
        return Accessory(id: id, name: name, kind: kind, parts: Array(parts.values), productID: productID, vendorID: vendorID)
    }

    private static func role(of description: [String: Any]) -> Accessory.Part.Role {
        switch (description[Key.partIdentifier] as? String)?.lowercased() {
        case "left": .left
        case "right": .right
        case "case": .case
        default: .single
        }
    }

    private static func part(from description: [String: Any], role: Accessory.Part.Role) -> Accessory.Part? {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int else { return nil }
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        guard max > 0, current >= 0 else { return nil }
        let percentage = Int((Double(current) / Double(max) * 100).rounded())
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        return Accessory.Part(role: role, percentage: percentage, isCharging: isCharging)
    }

    /// "Patrick's AirPods Pro Case" → "Patrick's AirPods Pro".
    private static func withoutCaseSuffix(_ name: String) -> String {
        for suffix in [" Case", " case"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    static func kind(categories: [String], name: String, roles: Set<Accessory.Part.Role>) -> Accessory.Kind {
        if roles.contains(.left) || roles.contains(.right) { return .earbuds }
        let words = (categories + [name]).joined(separator: " ").lowercased()
        if words.contains("mouse") { return .mouse }
        if words.contains("trackpad") { return .trackpad }
        if words.contains("keyboard") { return .keyboard }
        if words.contains("game") || words.contains("controller") { return .gameController }
        // A case on its own, before its earbuds have connected.
        if roles.contains(.case) || words.contains("battery case") { return .earbuds }
        if words.contains("headset") || words.contains("headphone") || words.contains("airpods") || words.contains("audio") {
            return .headphones
        }
        return .other
    }

    // MARK: - The HID registry

    /// Turns the properties of HID devices that report a battery (Magic Mouse,
    /// Keyboard, Trackpad) into accessories.
    public static func accessories(fromRegistry entries: [[String: Any]]) -> [Accessory] {
        var seen: Set<String> = []
        return entries.compactMap { properties -> Accessory? in
            // Right after connecting, the level can read 0 for a moment; a device that's really at 0% isn't connected.
            guard let percentage = properties[Key.batteryPercent] as? Int, percentage > 0,
                let name = properties[Key.product] as? String, !name.isEmpty
            else { return nil }
            let address = properties[Key.deviceAddress] as? String ?? properties[Key.serialNumber] as? String
            let id = "hid:" + (address ?? name)
            // A device can show up once per HID interface; one is enough.
            guard seen.insert(id).inserted else { return nil }
            // Magic accessories set this to 3 while charging over their cable.
            let isCharging = properties[Key.batteryStatusFlags] as? Int == 3
            return Accessory(
                id: id, name: name, kind: kind(categories: [], name: name, roles: [.single]),
                parts: [Accessory.Part(role: .single, percentage: percentage, isCharging: isCharging)],
                productID: properties[Key.registryProductID] as? Int, vendorID: properties[Key.registryVendorID] as? Int)
        }
    }

    /// Both sources together, in a steady order: headphones first, then by
    /// name. A device both of them know about is listed once, from
    /// IOPowerSources, which knows more about it. They can name it
    /// differently ("Patrick's Magic Keyboard" there, "Magic Keyboard" in the
    /// registry), so the same Apple product ID counts as the same device too.
    public static func merge(powerSources: [Accessory], registry: [Accessory]) -> [Accessory] {
        let names = Set(powerSources.map { normalized($0.name) })
        let products = Set(powerSources.compactMap { $0.isApple ? $0.productID : nil })
        let extra = registry.filter { accessory in
            if names.contains(normalized(accessory.name)) { return false }
            if accessory.isApple, let productID = accessory.productID, products.contains(productID) { return false }
            return true
        }
        return (powerSources + extra).sorted {
            ($0.kind, $0.name.localizedLowercase, $0.id) < ($1.kind, $1.name.localizedLowercase, $1.id)
        }
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    // MARK: - Reading

    /// `IOPSCopyPowerSourcesByType(kIOPSSourceForAccessories)`.
    private static func readPowerSources() -> [[String: Any]] {
        guard let copyByType = Symbols.copyPowerSourcesByType,
            let info = copyByType(Symbols.accessorySources)?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        return list.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
    }

    private static func readRegistry() -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(registryClass), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var entries: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            // Only the few properties needed, rather than copying every property of the device.
            var entry: [String: Any] = [:]
            for key in [
                Key.batteryPercent, Key.product, Key.deviceAddress, Key.serialNumber, Key.batteryStatusFlags, Key.registryProductID,
                Key.registryVendorID,
            ] {
                if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    entry[key] = value
                }
            }
            if entry[Key.batteryPercent] != nil { entries.append(entry) }
        }
        return entries
    }

    /// The registry class of HID devices that manage a battery.
    static let registryClass = "AppleDeviceManagementHIDEventService"

    private enum Key {
        static let accessoryType = "Accessory Source"
        static let groupIdentifier = "Group Identifier"
        static let accessoryIdentifier = "Accessory Identifier"
        static let partIdentifier = "Part Identifier"
        static let combinedParts = "Combined Parts"
        static let category = "Accessory Category"
        static let productID = "Product ID"
        static let vendorID = "Vendor ID"

        static let batteryPercent = "BatteryPercent"
        static let batteryStatusFlags = "BatteryStatusFlags"
        static let product = "Product"
        static let deviceAddress = "DeviceAddress"
        static let serialNumber = "SerialNumber"
        static let registryProductID = "ProductID"
        static let registryVendorID = "VendorID"
    }
}

/// IOKit functions for accessories that are exported but not in the SDK's headers, looked up once.
enum Symbols {
    typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    typealias CreateRunLoopSource = @convention(c) (IOPowerSourceCallbackType, UnsafeMutableRawPointer?) -> Unmanaged<CFRunLoopSource>?

    /// `kIOPSSourceForAccessories`.
    static let accessorySources: Int32 = 4

    nonisolated(unsafe) private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    static let copyPowerSourcesByType: CopyByType? = function("IOPSCopyPowerSourcesByType")
    /// Like `IOPSNotificationCreateRunLoopSource`, for accessories.
    static let accessoryNotification: CreateRunLoopSource? = function("IOPSAccNotificationCreateRunLoopSource")
    /// Fires when an accessory's power source is added or removed.
    static let accessoryAttachNotification: CreateRunLoopSource? = function("IOPSAccCreateAttachNotification")

    private static func function<T>(_ name: String) -> T? {
        guard let iokit, let symbol = dlsym(iokit, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
