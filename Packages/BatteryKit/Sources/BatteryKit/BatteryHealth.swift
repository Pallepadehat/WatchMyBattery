import Foundation
import IOKit

/// How worn the battery is: what System Settings › Battery › Battery Health shows.
public struct BatteryHealth: Sendable, Equatable {
    public enum Condition: Sendable, Equatable {
        case normal
        /// macOS recommends having the battery serviced.
        case serviceRecommended
    }

    public var condition: Condition?
    /// How much charge the battery holds compared with when it was new, 0–1.
    public var maximumCapacity: Double?
    public var cycleCount: Int?

    public init(condition: Condition?, maximumCapacity: Double?, cycleCount: Int?) {
        self.condition = condition
        self.maximumCapacity = maximumCapacity.map { min(max($0, 0), 1.5) }
        self.cycleCount = cycleCount
    }

    /// Nothing worth showing.
    public var isEmpty: Bool { condition == nil && maximumCapacity == nil && cycleCount == nil }
}

/// Reads ``BatteryHealth``.
///
/// macOS's own figures (the ones System Settings shows) come from
/// `system_profiler`, which takes a fraction of a second, so it runs off the
/// main thread and rarely: health changes over months, not minutes. If that
/// fails, the cycle count and an approximate capacity come straight from the
/// battery controller in the IORegistry.
public enum BatteryHealthReader {
    public static func read() async -> BatteryHealth? {
        let task = Task.detached(priority: .utility) { () -> BatteryHealth? in
            if let json = runSystemProfiler(), let health = parse(systemProfilerJSON: json), !health.isEmpty {
                return health
            }
            return readRegistry()
        }
        return await task.value
    }

    /// Parses `system_profiler SPPowerDataType -json`.
    public static func parse(systemProfilerJSON data: Data) -> BatteryHealth? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["SPPowerDataType"] as? [[String: Any]],
            let info = items.lazy.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first
        else { return nil }

        let condition: BatteryHealth.Condition? =
            switch (info["sppower_battery_health"] as? String)?.lowercased() {
            case nil: nil
            case "good", "normal": .normal
            default: .serviceRecommended
            }
        // "88 %" (with a no-break space), "88%" or a plain number.
        var capacity: Double?
        if let text = info["sppower_battery_health_maximum_capacity"] as? String {
            let digits = text.filter { $0.isNumber || $0 == "." }
            capacity = Double(digits).map { $0 / 100 }
        } else if let number = info["sppower_battery_health_maximum_capacity"] as? Double {
            capacity = number > 1.5 ? number / 100 : number
        }
        let cycles = info["sppower_battery_cycle_count"] as? Int
        return BatteryHealth(condition: condition, maximumCapacity: capacity, cycleCount: cycles)
    }

    /// The battery controller's own numbers: exact for cycles, close for capacity.
    public static func health(fromRegistry properties: [String: Any]) -> BatteryHealth? {
        let cycles = properties["CycleCount"] as? Int
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        let design = (properties["DesignCapacity"] as? Int) ?? (data["DesignCapacity"] as? Int)
        let full =
            (properties["NominalChargeCapacity"] as? Int) ?? (data["NominalChargeCapacity"] as? Int)
            ?? (properties["AppleRawMaxCapacity"] as? Int)
        var capacity: Double?
        if let design, let full, design > 0 { capacity = Double(full) / Double(design) }
        let health = BatteryHealth(condition: nil, maximumCapacity: capacity, cycleCount: cycles)
        return health.isEmpty ? nil : health
    }

    private static func runSystemProfiler() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json", "-detailLevel", "mini"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func readRegistry() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return health(fromRegistry: dictionary)
    }
}
