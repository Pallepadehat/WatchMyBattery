import Foundation

/// Plugging in or unplugging, as the chime hears it.
public enum PowerChange: Sendable, Equatable {
    case pluggedIn
    case unplugged
}

/// Decides when plugging in or unplugging deserves a chime.
///
/// Only a change you made: not the power source the app finds when it opens, not one that happened while the Mac
/// slept (it shows up on waking, long after the fact), and not every flicker of a loose cable.
public struct PowerChangeDetector: Sendable {
    private var source: BatterySnapshot.PowerSource?
    private var lastChime: Date?
    private var quietUntil: Date?

    /// The shortest time between two chimes, so a loose cable doesn't chatter.
    public static let minimumInterval: TimeInterval = 2
    /// How long after waking a change counts as old news. A charger plugged in within these few seconds of opening the
    /// lid goes unheard too: a fair price for never chiming about one plugged in during the night.
    public static let quietAfterWake: TimeInterval = 4

    public init() {}

    /// The change worth a chime, given the power source at `now`.
    public mutating func update(_ snapshot: BatterySnapshot, at now: Date) -> PowerChange? {
        guard snapshot.hasBattery else { return nil }
        let previous = source
        source = snapshot.powerSource
        guard let previous, previous != snapshot.powerSource else { return nil }
        if let quietUntil, now < quietUntil { return nil }
        if let lastChime, now.timeIntervalSince(lastChime) < Self.minimumInterval { return nil }
        lastChime = now
        return snapshot.isPluggedIn ? .pluggedIn : .unplugged
    }

    /// The Mac is going to sleep: nothing it hears until it wakes is worth a chime. (macOS can announce a new power
    /// source a moment before it says the Mac woke.)
    public mutating func willSleep() {
        quietUntil = .distantFuture
    }

    /// The Mac just woke: changes for the next few seconds happened while it slept.
    public mutating func didWake(at now: Date) {
        quietUntil = now.addingTimeInterval(Self.quietAfterWake)
    }
}

/// WatchMyBattery's own chime: two soft bell notes, rising a fifth when you plug in and falling when you unplug,
/// made on the spot as a little WAV file, so there's no sound file to ship.
public enum ChimeSynth {
    public static let sampleRate = 44_100
    /// Peak loudness, 0–1: gentle next to the system's alerts.
    static let peak = 0.45
    /// The notes, in hertz: E5 and the B above it.
    static let lowNote = 659.25
    static let highNote = 987.77
    /// When the second note starts, and how long the whole chime rings.
    static let secondNoteStart: TimeInterval = 0.12
    static let duration: TimeInterval = 1.1

    /// The chime for a change, as WAV data that `NSSound(data:)` plays.
    public static func wav(for change: PowerChange) -> Data {
        WAV.encode(samples(for: change), sampleRate: sampleRate)
    }

    /// The chime's samples, -1…1.
    public static func samples(for change: PowerChange) -> [Double] {
        let (first, second) = change == .pluggedIn ? (lowNote, highNote) : (highNote, lowNote)
        let count = Int(duration * Double(sampleRate))
        var samples = [Double](repeating: 0, count: count)
        addBell(at: first, startingAt: 0, loudness: 0.8, into: &samples)
        addBell(at: second, startingAt: secondNoteStart, loudness: 1, into: &samples)
        fadeOut(&samples)
        let loudest = samples.lazy.map(abs).max() ?? 0
        guard loudest > 0 else { return samples }
        return samples.map { $0 / loudest * peak }
    }

    /// A bell-like note: a pure tone with a few quieter overtones, a quick soft attack, and a long fade, the higher
    /// overtones fading first, as a struck glass does.
    private static func addBell(at frequency: Double, startingAt start: TimeInterval, loudness: Double, into samples: inout [Double]) {
        let overtones: [(ratio: Double, level: Double, decay: Double)] = [(1, 1, 0.42), (2, 0.28, 0.2), (3, 0.08, 0.12), (4.2, 0.05, 0.06)]
        let attack = 0.006
        let first = Int(start * Double(sampleRate))
        for index in first..<samples.count {
            let t = Double(index - first) / Double(sampleRate)
            let rise = min(t / attack, 1)
            var value = 0.0
            for overtone in overtones {
                value += overtone.level * exp(-t / overtone.decay) * sin(2 * .pi * frequency * overtone.ratio * t)
            }
            samples[index] += loudness * rise * value
        }
    }

    /// The last few milliseconds fade to silence, so the end never clicks.
    private static func fadeOut(_ samples: inout [Double]) {
        let tail = min(Int(0.02 * Double(sampleRate)), samples.count)
        for offset in 0..<tail {
            samples[samples.count - 1 - offset] *= Double(offset) / Double(tail)
        }
    }
}

/// The smallest WAV file there is: 16-bit mono PCM.
enum WAV {
    static func encode(_ samples: [Double], sampleRate: Int) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian: UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.append(littleEndian: UInt32(16))  // the size of the format chunk
        data.append(littleEndian: UInt16(1))  // PCM
        data.append(littleEndian: UInt16(1))  // mono
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(sampleRate * bytesPerSample))  // bytes a second
        data.append(littleEndian: UInt16(bytesPerSample))  // bytes a frame
        data.append(littleEndian: UInt16(16))  // bits a sample
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian: UInt32(dataSize))
        for sample in samples {
            data.append(littleEndian: Int16((min(max(sample, -1), 1) * Double(Int16.max)).rounded()))
        }
        return data
    }
}

extension Data {
    fileprivate mutating func append<Value: FixedWidthInteger>(littleEndian value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
