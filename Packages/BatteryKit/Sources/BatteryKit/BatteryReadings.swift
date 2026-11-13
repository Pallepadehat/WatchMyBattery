import Foundation
import IOKit

/// The battery's electrical state right now: what the battery controller measures.
public struct BatteryReadings: Sendable, Equatable {
    /// Degrees Celsius.
    public var temperature: Double?
    /// Volts.
    public var voltage: Double?
    /// Amps: positive flowing into the battery (charging), negative out of it.
    public var current: Double?

    public init(temperature: Double? = nil, voltage: Double? = nil, current: Double? = nil) {
        self.temperature = temperature
        self.voltage = voltage
        self.current = current
    }

    public var isEmpty: Bool { temperature == nil && voltage == nil && current == nil }

    /// Watts in (positive) or out (negative) of the battery itself, not the whole Mac: on the adapter, the Mac runs
    /// from the adapter and this is only what the battery takes.
    public var batteryWatts: Double? {
        guard let voltage, let current else { return nil }
        return voltage * current
    }

    /// How warm the battery is, as a lithium-ion cell sees it.
    public var warmth: Warmth? {
        guard let temperature else { return nil }
        if temperature >= Warmth.hotFrom { return .hot }
        if temperature >= Warmth.warmFrom { return .warm }
        return .normal
    }

    public enum Warmth: Sendable, Equatable {
        case normal
        /// Charging slows down around here, and time spent this warm wears a battery faster.
        case warm
        /// macOS will hold back charging.
        case hot

        public static let warmFrom = 35.0
        public static let hotFrom = 40.0
    }

    /// Changed enough to be worth redrawing: a tenth of a degree, a hundredth of a volt or amp is noise.
    public func differsVisibly(from other: BatteryReadings) -> Bool {
        func moved(_ a: Double?, _ b: Double?, by step: Double) -> Bool {
            switch (a, b) {
            case (nil, nil): false
            case (let a?, let b?): abs(a - b) >= step
            default: true
            }
        }
        return moved(temperature, other.temperature, by: 0.5) || moved(voltage, other.voltage, by: 0.02)
            || moved(current, other.current, by: 0.05)
    }
}

/// Reads ``BatteryReadings`` from the battery controller (the `AppleSmartBattery` IORegistry entry), and the
/// temperature from the System Management Controller when the registry no longer has it (it moved there in
/// recent macOS versions). Both are read-only and need no permission; a reading takes a fraction of a millisecond.
public final class BatteryReadingsReader: @unchecked Sendable {
    private let service: io_service_t
    private let smc = SMCReader()

    public init() {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    deinit {
        if service != IO_OBJECT_NULL { IOObjectRelease(service) }
    }

    public func read() -> BatteryReadings {
        guard service != IO_OBJECT_NULL else { return BatteryReadings() }
        var properties: [String: Any] = [:]
        for key in Self.registryKeys {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                properties[key] = value
            }
        }
        var readings = Self.readings(fromRegistry: properties)
        if readings.temperature == nil {
            readings.temperature = Self.temperature(fromSMC: Self.smcTemperatureKeys.compactMap { smc.readFloat($0) })
        }
        return readings
    }

    static let registryKeys = ["Voltage", "InstantAmperage", "Amperage", "Temperature", "VirtualTemperature"]
    /// The battery's temperature sensors.
    static let smcTemperatureKeys = ["TB0T", "TB1T", "TB2T"]

    /// From the registry's properties. Separate so it can be tested with made-up ones.
    public static func readings(fromRegistry properties: [String: Any]) -> BatteryReadings {
        let millivolts = properties["Voltage"] as? Int
        let milliamps = (properties["InstantAmperage"] ?? properties["Amperage"]) as? Int
        // Hundredths of a degree Celsius, where it's still there.
        let centidegrees = (properties["Temperature"] ?? properties["VirtualTemperature"]) as? Int
        return BatteryReadings(
            temperature: centidegrees.flatMap { $0 > 0 ? Double($0) / 100 : nil }.flatMap(plausibleTemperature),
            voltage: millivolts.flatMap { $0 > 0 ? Double($0) / 1000 : nil },
            current: milliamps.map { Double($0) / 1000 }
        )
    }

    /// The average of the sensors that read something sensible.
    public static func temperature(fromSMC values: [Double]) -> Double? {
        let sensible = values.compactMap(plausibleTemperature)
        guard !sensible.isEmpty else { return nil }
        return sensible.reduce(0, +) / Double(sensible.count)
    }

    private static func plausibleTemperature(_ celsius: Double) -> Double? {
        (-20...90).contains(celsius) ? celsius : nil
    }
}

/// Reads values from the System Management Controller, the chip that runs charging, fans and sensors. Read-only:
/// WatchMyBattery never writes to it (the charge limit goes through macOS, see ``ChargeLimitClient``).
final class SMCReader: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != kIOReturnSuccess { connection = 0 }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// A key holding a 32-bit float (`flt `), such as a temperature sensor's.
    func readFloat(_ key: String) -> Double? {
        guard let (type, bytes) = read(key), type == "flt ", bytes.count == 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return Double(Float(bitPattern: bits))
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard connection != 0, let code = Self.fourCharCode(key) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        var info = Parameters()
        info.key = code
        info.command = Command.keyInfo
        guard call(&info), info.result == 0 else { return nil }
        var value = Parameters()
        value.key = code
        value.keyInfo = info.keyInfo
        value.command = Command.readBytes
        guard call(&value), value.result == 0 else { return nil }
        let size = min(Int(info.keyInfo.dataSize), 32)
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(size)) }
        return (Self.string(from: info.keyInfo.dataType), bytes)
    }

    private func call(_ parameters: inout Parameters) -> Bool {
        var output = Parameters()
        var size = MemoryLayout<Parameters>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.selector, &parameters, MemoryLayout<Parameters>.stride, &output, &size)
        parameters = output
        return result == kIOReturnSuccess
    }

    private static let selector: UInt32 = 2

    private enum Command {
        static let readBytes: UInt8 = 5
        static let keyInfo: UInt8 = 9
    }

    private static func fourCharCode(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, as: UTF8.self)
    }

    /// The SMC's request and reply, laid out as the kernel driver expects (80 bytes).
    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct Parameters {
        var key: UInt32 = 0
        var version: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var limits: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }
}
