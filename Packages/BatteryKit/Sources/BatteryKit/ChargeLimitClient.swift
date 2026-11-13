import Foundation
import ObjectiveC

/// macOS's own Charge Limit: System Settings › Battery › Charging › Charge Limit, from macOS 26.4 on Apple silicon.
///
/// Rather than writing to the System Management Controller ourselves (as charge limiters did before macOS had one),
/// WatchMyBattery asks macOS to hold the battery where you choose. macOS then does what it does for its own setting:
/// stops charging at the limit and runs the Mac from the adapter, keeps Optimized Battery Charging in step, and keeps
/// the limit through restarts and updates, with or without WatchMyBattery running. Nothing needs root, and nothing
/// can leave the battery in a state macOS doesn't know about.
///
/// The setting lives in PowerUI's `PowerUISmartChargeClient`, the same client System Settings and the Shortcuts
/// action "Set Battery Charge Limit" use. It isn't in the public SDK, so it's looked up at runtime and every
/// selector is checked first: on a Mac or macOS version without it, ``isAvailable`` is `false` and nothing breaks.
///
/// Each call is a round trip to `PowerUIAgent` over XPC, so call it off the main thread.
public final class ChargeLimitClient: @unchecked Sendable {
    /// The levels macOS offers, lowest first: 80, 85, 90, 95 and 100 today.
    public struct Levels: Sendable, Equatable {
        public var choices: [Int]

        public init(_ choices: [Int]) {
            self.choices = choices.filter { (1...100).contains($0) }.sorted()
        }

        /// 100 means no limit.
        public static let noLimit = 100
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case unavailable
        case notAChoice(Int)
        case refused(String)

        public var errorDescription: String? {
            switch self {
            case .unavailable: "This Mac doesn't have a charge limit."
            case .notAChoice(let level): "macOS doesn't offer a \(level)% charge limit."
            case .refused(let message): message
            }
        }
    }

    private let client: NSObject?
    private let lock = NSLock()

    public init(clientName: String = "WatchMyBattery") {
        client = Self.makeClient(named: clientName)
    }

    /// This Mac and macOS version have a charge limit WatchMyBattery can set.
    public var isAvailable: Bool { client != nil && !(levels()?.choices.isEmpty ?? true) }

    /// The levels the limit can be set to, or `nil` without a charge limit.
    public func levels() -> Levels? {
        guard let client else { return nil }
        typealias Function = @convention(c) (NSObject, ObjectiveC.Selector, UnsafeMutablePointer<NSError?>) -> NSArray?
        guard let call: Function = Self.function(client, Selectors.available) else { return nil }
        var error: NSError?
        let choices = locked { call(client, Selectors.available, &error) }
        guard error == nil, let numbers = choices as? [NSNumber] else { return nil }
        return Levels(numbers.map(\.intValue))
    }

    /// The limit macOS is holding the battery to, 1–100; 100 when there's none.
    public func current() -> Int? {
        guard let client else { return nil }
        typealias Function = @convention(c) (NSObject, ObjectiveC.Selector, UnsafeMutablePointer<NSError?>) -> UInt8
        guard let call: Function = Self.function(client, Selectors.getManual) else { return nil }
        var error: NSError?
        let value = locked { call(client, Selectors.getManual, &error) }
        guard error == nil, (1...100).contains(value) else { return nil }
        return Int(value)
    }

    /// Asks macOS to hold the battery at `level`, one of ``levels()``; 100 lifts the limit. Reads it back
    /// afterwards, so a request macOS quietly ignored still fails.
    public func set(_ level: Int) throws(Failure) {
        guard let client, let levels = levels() else { throw .unavailable }
        guard levels.choices.contains(level) else { throw .notAChoice(level) }
        typealias Function = @convention(c) (NSObject, ObjectiveC.Selector, UInt8, UnsafeMutablePointer<NSError?>) -> Bool
        guard let call: Function = Self.function(client, Selectors.setManual) else { throw .unavailable }
        var error: NSError?
        let worked = locked { call(client, Selectors.setManual, UInt8(level), &error) }
        if let error { throw .refused(error.localizedDescription) }
        guard worked, current() == level else { throw .refused("macOS didn't take the new charge limit.") }
    }

    // MARK: - The runtime

    private enum Selectors {
        static let available = NSSelectorFromString("availableChargeLimitsWithError:")
        static let getManual = NSSelectorFromString("getMCLLimitWithError:")
        static let setManual = NSSelectorFromString("setMCLLimit:error:")
        static let initialize = NSSelectorFromString("initWithClientName:")
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI"

    private static func makeClient(named name: String) -> NSObject? {
        guard dlopen(frameworkPath, RTLD_LAZY) != nil,
            let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
            [Selectors.available, Selectors.getManual, Selectors.setManual].allSatisfy(type.instancesRespond(to:)),
            type.instancesRespond(to: Selectors.initialize)
        else { return nil }
        typealias Initializer = @convention(c) (AnyObject, ObjectiveC.Selector, NSString) -> NSObject?
        guard let implementation = class_getMethodImplementation(type, Selectors.initialize) else { return nil }
        let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        guard let allocated else { return nil }
        return unsafeBitCast(implementation, to: Initializer.self)(allocated, Selectors.initialize, name as NSString)
    }

    /// The method's implementation, as a function of the given type, when the object has it.
    private static func function<T>(_ object: NSObject, _ selector: ObjectiveC.Selector) -> T? {
        guard object.responds(to: selector), let implementation = object.method(for: selector) else { return nil }
        return unsafeBitCast(implementation, to: T.self)
    }

    /// One request at a time: the client isn't documented as safe to share between threads.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
