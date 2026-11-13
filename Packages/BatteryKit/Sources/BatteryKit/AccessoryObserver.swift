import CoreFoundation
import Foundation
import IOKit
import IOKit.ps

/// Calls you back when an accessory connects, disconnects, or its battery
/// changes. macOS pushes all of these, so there's no polling:
///
/// - IOPowerSources' accessory notifications, for AirPods and others it publishes;
/// - the IOKit registry's notifications for devices with a `BatteryPercent`
///   (Magic Mouse, Keyboard, Trackpad) appearing and going away, reported
///   apart, as only then does ``AccessoryRegistry`` need to search again.
///
/// The registry doesn't announce a changed `BatteryPercent`, so the owner
/// reads those at other moments too (see `AccessoryMonitor`).
@MainActor
public final class AccessoryObserver {
    private let onChange: @MainActor () -> Void
    private let onDevicesChanged: @MainActor () -> Void
    private var sources: [CFRunLoopSource] = []
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    /// `onChange` for any change; `onDevicesChanged` when a device with a `BatteryPercent` comes or goes.
    public init(onChange: @escaping @MainActor () -> Void, onDevicesChanged: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        self.onDevicesChanged = onDevicesChanged
    }

    public func start() {
        guard sources.isEmpty, notificationPort == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            // IOKit calls back on the run loop the source was added to: the main one.
            MainActor.assumeIsolated {
                Unmanaged<AccessoryObserver>.fromOpaque(context).takeUnretainedValue().onChange()
            }
        }
        // The general notification too: it comes about once a minute anyway, and it's a safety net should a
        // macOS version stop sending the accessory ones.
        let general: Symbols.CreateRunLoopSource = { IOPSNotificationCreateRunLoopSource($0, $1) }
        for create in [Symbols.accessoryNotification, Symbols.accessoryAttachNotification, general].compactMap(\.self) {
            guard let source = create(callback, context)?.takeRetainedValue() else { continue }
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            sources.append(source)
        }

        // Magic accessories come and go in the registry.
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let matched: IOServiceMatchingCallback = { context, iterator in
            // The iterator has to be drained, or no more notifications arrive.
            while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL { IOObjectRelease(service) }
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<AccessoryObserver>.fromOpaque(context).takeUnretainedValue().onDevicesChanged()
            }
        }
        // By the property, and by the class Magic accessories use today: the property match is only checked as a
        // device is registered, so one whose level is set a moment later is caught by its class instead.
        let matchings = { [AccessoryRegistry.matching(), IOServiceMatching(AccessoryRegistry.knownClass)].compactMap(\.self) }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            for matching in matchings() {
                var iterator: io_iterator_t = 0
                let result = IOServiceAddMatchingNotification(port, type, matching, matched, context, &iterator)
                guard result == KERN_SUCCESS else { continue }
                // Drain once to arm it; the devices already there are read separately.
                while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL { IOObjectRelease(service) }
                iterators.append(iterator)
            }
        }
    }

    public func stop() {
        for source in sources { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        sources.removeAll()
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        notificationPort = nil
    }

    isolated deinit {
        stop()
    }
}
