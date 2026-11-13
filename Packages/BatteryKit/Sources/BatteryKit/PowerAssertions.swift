import Foundation
import IOKit.pwr_mgt

/// A process asking macOS not to sleep: what `pmset -g assertions` lists under "Listed by owning process".
///
/// Apps take these to finish a download, play a video, keep a call going, or because they forgot to let go. While
/// one that keeps the system awake is held, closing the lid on the adapter, or walking away on battery, doesn't put
/// the Mac to sleep, which is how "I left it at 80% and came back to 40%" happens.
public struct PowerAssertion: Sendable, Equatable, Identifiable {
    public enum Effect: Int, Sendable, Equatable, Comparable {
        /// Keeps the screen on (and so the Mac awake).
        case keepsDisplayOn
        /// Keeps the Mac from sleeping when idle, while the screen may turn off.
        case keepsSystemAwake

        public static func < (lhs: Effect, rhs: Effect) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: Int
    public var pid: pid_t
    /// The process's own name, as macOS reports it ("caffeinate", "zoom.us").
    public var processName: String
    /// What the process said it's for ("Playing audio", "Downloading update").
    public var reason: String
    public var effect: Effect
    public var since: Date?
    /// The process it's really for, when a part of macOS holds it for an app: `coreaudiod` keeps the Mac awake for
    /// whatever is playing sound.
    public var onBehalfOf: pid_t?
    /// What it's using, as macOS lists it: "audio-out", "audio-in", a device's name.
    public var resources: [String]

    public init(
        id: Int, pid: pid_t, processName: String, reason: String, effect: Effect, since: Date?, onBehalfOf: pid_t? = nil,
        resources: [String] = []
    ) {
        self.id = id
        self.pid = pid
        self.processName = processName
        self.reason = reason
        self.effect = effect
        self.since = since
        self.onBehalfOf = onBehalfOf
        self.resources = resources
    }

    /// The process that wants the Mac awake: the app it's held for, or else the one holding it.
    public var owner: pid_t { onBehalfOf.flatMap { $0 > 0 ? $0 : nil } ?? pid }

    /// Sound is playing.
    public var isPlayingAudio: Bool { resources.contains("audio-out") }
    /// The microphone is on.
    public var isRecordingAudio: Bool { resources.contains("audio-in") }
}

/// Reads ``PowerAssertion``s with `IOPMCopyAssertionsByProcess`, a public IOKit call that needs no permission and
/// takes well under a millisecond.
public enum PowerAssertionReader {
    public static func read() -> [PowerAssertion] {
        var dictionary: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dictionary) == kIOReturnSuccess,
            let byProcess = dictionary?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        return assertions(from: Dictionary(uniqueKeysWithValues: byProcess.map { (pid_t($0.key.int32Value), $0.value) }))
    }

    /// The ones that keep the Mac awake, longest held first. Separate from ``read()`` so it can be tested with
    /// made-up dictionaries.
    public static func assertions(from byProcess: [pid_t: [[String: Any]]]) -> [PowerAssertion] {
        var result: [PowerAssertion] = []
        for (pid, list) in byProcess {
            for entry in list {
                let type = entry[Key.trueType] as? String ?? entry[Key.type] as? String ?? ""
                guard let effect = effect(of: type), entry[Key.level] as? Int ?? 255 != 0 else { continue }
                let name = entry[Key.processName] as? String ?? ""
                let reason = entry[Key.name] as? String ?? ""
                guard !isMacOSItself(processName: name, reason: reason) else { continue }
                let id = entry[Key.id] as? Int ?? entry[Key.globalID] as? Int ?? (Int(pid) << 16 | result.count)
                let onBehalfOf = (entry[Key.onBehalfOf] as? Int).map { pid_t($0) }
                result.append(
                    PowerAssertion(
                        id: id, pid: pid, processName: name, reason: reason, effect: effect, since: entry[Key.start] as? Date,
                        onBehalfOf: onBehalfOf, resources: entry[Key.resources] as? [String] ?? []))
            }
        }
        return result.sorted { ($0.since ?? .distantFuture, $0.id) < ($1.since ?? .distantFuture, $1.id) }
    }

    static func effect(of type: String) -> PowerAssertion.Effect? {
        switch type {
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion": .keepsDisplayOn
        case "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion", "DenySystemSleep": .keepsSystemAwake
        default: nil
        }
    }

    /// macOS keeps itself awake while the screen is on, and while you're typing or moving the pointer: true, but
    /// not something you can or should do anything about.
    static func isMacOSItself(processName: String, reason: String) -> Bool {
        (processName == "powerd" && reason.hasPrefix("Powerd - Prevent sleep while display is on"))
            || processName == "WindowServer"
    }

    private enum Key {
        static let type = "AssertType"
        static let trueType = "AssertionTrueType"
        static let name = "AssertName"
        static let level = "AssertLevel"
        static let processName = "Process Name"
        static let start = "AssertStartWhen"
        static let id = "AssertionId"
        static let globalID = "GlobalUniqueID"
        static let onBehalfOf = "AssertionOnBehalfOfPID"
        static let resources = "ResourcesUsed"
    }
}
