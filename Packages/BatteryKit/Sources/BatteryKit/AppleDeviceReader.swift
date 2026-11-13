import Foundation

/// Reads the battery of an iPhone or iPad that trusts this Mac, the way Finder and coconutBattery do: through the
/// MobileDevice framework, over its cable, or over Wi‑Fi when "Show this iPhone when on Wi‑Fi" is turned on in
/// Finder.
///
/// It never asks a device to trust this Mac: one that hasn't is skipped, so nothing pops up on the phone. macOS
/// announces devices as they come and go; their levels aren't announced, so they're read when a device arrives,
/// when the panel opens, and now and then while one is connected.
///
/// MobileDevice isn't in the public SDK, so its functions are looked up at runtime; without them this simply finds
/// nothing. An Apple Watch talks only to its iPhone, so it can't be read from a Mac this way.
public final class AppleDeviceReader: @unchecked Sendable {
    /// A device came or went.
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    /// The devices macOS knows about, by identifier, each with a handle for every way it's connected (a phone on its
    /// cable is often on Wi‑Fi too, and stays there when the cable comes out).
    private var devices: [String: [Int32: CFTypeRef]] = [:]
    private let queue = DispatchQueue(label: "com.pallepadehat.WatchMyBattery.devices", qos: .utility)
    private var isSubscribed = false

    public init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    /// The framework is there, so devices can be found.
    public static var isAvailable: Bool { Functions.shared != nil }

    /// Starts hearing about devices. Call on the main thread: macOS announces them on its run loop.
    public func start() {
        guard !isSubscribed, let functions = Functions.shared else { return }
        isSubscribed = true
        var subscription: UnsafeMutableRawPointer?
        let context = Unmanaged.passUnretained(self).toOpaque()
        _ = functions.subscribe(Self.callback, 0, 0, context, &subscription)
    }

    /// Reads every trusted device's battery, off the calling thread. Wi‑Fi devices can take a moment to answer.
    public func read() async -> [Accessory] {
        // The cable where there is one: it answers faster.
        let devices = Devices(
            list: lock.withLock {
                self.devices.compactMapValues { connections in
                    connections[Interface.usb] ?? connections.sorted { $0.key < $1.key }.first?.value
                }
            })
        guard !devices.list.isEmpty, let functions = Functions.shared else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async {
                let accessories = devices.list.compactMap { id, device in Self.read(device, id: id, functions: functions) }
                continuation.resume(returning: accessories.sorted { $0.name.localizedLowercase < $1.name.localizedLowercase })
            }
        }
    }

    /// Device handles, handed to the reading queue. MobileDevice's handles can be used from any thread.
    private struct Devices: @unchecked Sendable {
        let list: [String: CFTypeRef]
    }

    /// Whether any device is connected, so it's worth reading now and then.
    public var hasDevices: Bool { lock.withLock { !devices.isEmpty } }

    // MARK: - Turning what a device says into an accessory

    /// From the values a device reported. Separate so it can be tested with made-up ones.
    public static func accessory(id: String, values: [String: Any]) -> Accessory? {
        guard let level = values[Key.batteryLevel] as? Int, (0...100).contains(level) else { return nil }
        let deviceClass = (values[Key.deviceClass] as? String ?? "").lowercased()
        let product = (values[Key.productType] as? String ?? "").lowercased()
        let kind: Accessory.Kind =
            if deviceClass == "ipad" || product.hasPrefix("ipad") {
                .tablet
            } else if deviceClass == "watch" || product.hasPrefix("watch") {
                .watch
            } else {
                .phone
            }
        let name = values[Key.deviceName] as? String ?? (kind == .tablet ? "iPad" : "iPhone")
        let isCharging = values[Key.isCharging] as? Bool ?? false
        return Accessory(
            id: "device:" + id, name: name, kind: kind, parts: [Accessory.Part(role: .single, percentage: level, isCharging: isCharging)],
            vendorID: Accessory.appleVendorID)
    }

    private enum Key {
        static let deviceName = "DeviceName"
        static let deviceClass = "DeviceClass"
        static let productType = "ProductType"
        static let batteryLevel = "BatteryCurrentCapacity"
        static let isCharging = "BatteryIsCharging"
        static let batteryDomain = "com.apple.mobile.battery"
    }

    // MARK: - MobileDevice

    private static func read(_ device: CFTypeRef, id: String, functions: Functions) -> Accessory? {
        let pointer = Unmanaged.passUnretained(device).toOpaque()
        guard functions.connect(pointer) == 0 else { return nil }
        defer { _ = functions.disconnect(pointer) }
        // Only a device that already trusts this Mac. Validating doesn't ask the phone anything.
        guard functions.isPaired(pointer) == 1, functions.validatePairing(pointer) == 0, functions.startSession(pointer) == 0 else {
            return nil
        }
        defer { _ = functions.stopSession(pointer) }
        var values: [String: Any] = [:]
        for key in [Key.deviceName, Key.deviceClass, Key.productType] {
            values[key] = functions.copyValue(pointer, nil, key as CFString)?.takeRetainedValue()
        }
        for key in [Key.batteryLevel, Key.isCharging] {
            values[key] = functions.copyValue(pointer, Key.batteryDomain as CFString, key as CFString)?.takeRetainedValue()
        }
        return accessory(id: id, values: values)
    }

    /// Called with a `struct am_device_notification_callback_info`: the device, then what happened to it.
    private static let callback: Functions.Callback = { info, context in
        guard let info, let context, let device = info.load(as: UnsafeMutableRawPointer?.self) else { return }
        let message = info.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        let reader = Unmanaged<AppleDeviceReader>.fromOpaque(context).takeUnretainedValue()
        reader.handle(device: device, message: message)
    }

    private func handle(device pointer: UnsafeMutableRawPointer, message: UInt32) {
        guard let functions = Functions.shared,
            let id = functions.copyIdentifier(pointer)?.takeRetainedValue() as String?
        else { return }
        let interface = functions.interfaceType(pointer)
        let device = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
        let changed: Bool = lock.withLock {
            switch message {
            case Message.connected:
                devices[id, default: [:]][interface] = device
                return true
            case Message.disconnected:
                guard devices[id]?[interface] != nil else { return false }
                devices[id]?[interface] = nil
                if devices[id]?.isEmpty == true { devices[id] = nil }
                return true
            default:
                // Paired (the phone's "Trust" was just tapped) and the like: a device that couldn't be read a moment
                // ago may answer now.
                return devices[id] != nil
            }
        }
        if changed { onChange() }
    }

    private enum Message {
        static let connected: UInt32 = 1
        static let disconnected: UInt32 = 2
    }

    private enum Interface {
        static let usb: Int32 = 1
    }

    /// MobileDevice's functions, looked up once.
    private struct Functions {
        typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        typealias Subscribe =
            @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
        typealias DeviceCall = @convention(c) (UnsafeMutableRawPointer) -> Int32
        typealias CopyIdentifier = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFString>?
        typealias CopyValue = @convention(c) (UnsafeMutableRawPointer, CFString?, CFString) -> Unmanaged<CFTypeRef>?

        let subscribe: Subscribe
        let connect: DeviceCall
        let disconnect: DeviceCall
        let isPaired: DeviceCall
        let validatePairing: DeviceCall
        let startSession: DeviceCall
        let stopSession: DeviceCall
        let interfaceType: DeviceCall
        let copyIdentifier: CopyIdentifier
        let copyValue: CopyValue

        static let shared: Functions? = {
            let paths = [
                "/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
                "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
            ]
            guard let handle = paths.lazy.compactMap({ dlopen($0, RTLD_LAZY) }).first else { return nil }
            func symbol<T>(_ name: String) -> T? {
                dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
            }
            guard let subscribe: Subscribe = symbol("AMDeviceNotificationSubscribe"),
                let connect: DeviceCall = symbol("AMDeviceConnect"),
                let disconnect: DeviceCall = symbol("AMDeviceDisconnect"),
                let isPaired: DeviceCall = symbol("AMDeviceIsPaired"),
                let validatePairing: DeviceCall = symbol("AMDeviceValidatePairing"),
                let startSession: DeviceCall = symbol("AMDeviceStartSession"),
                let stopSession: DeviceCall = symbol("AMDeviceStopSession"),
                let interfaceType: DeviceCall = symbol("AMDeviceGetInterfaceType"),
                let copyIdentifier: CopyIdentifier = symbol("AMDeviceCopyDeviceIdentifier"),
                let copyValue: CopyValue = symbol("AMDeviceCopyValue")
            else { return nil }
            return Functions(
                subscribe: subscribe, connect: connect, disconnect: disconnect, isPaired: isPaired, validatePairing: validatePairing,
                startSession: startSession, stopSession: stopSession, interfaceType: interfaceType, copyIdentifier: copyIdentifier,
                copyValue: copyValue)
        }()
    }
}
