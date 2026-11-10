import CoreFoundation
import Foundation
import IOKit.ps

/// Calls you back whenever anything about the power sources changes: the
/// charge level, the adapter, the time estimate. macOS pushes these, so
/// there's no polling.
@MainActor
public final class PowerSourceObserver {
    private let onChange: @MainActor () -> Void
    private var source: CFRunLoopSource?

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    public func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            // IOKit calls back on the run loop the source was added to: the main one.
            MainActor.assumeIsolated {
                Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue().onChange()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    public func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = nil
    }

    isolated deinit {
        stop()
    }
}
