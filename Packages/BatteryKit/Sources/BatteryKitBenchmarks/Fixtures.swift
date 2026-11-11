import BatteryKit
import Foundation

/// Made-up but realistic data: what the app holds after a long day.
enum Fixtures {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Apps that show up in the history, more than fit in one sample, so they come and go.
    static let apps: [BatteryHistory.AppIdentity] = (0..<40).map {
        BatteryHistory.AppIdentity(name: "App \($0)", bundleIdentifier: "com.example.app\($0)")
    }

    static func snapshot(_ percentage: Int, pluggedIn: Bool) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery,
            chargeState: pluggedIn ? .charging : .discharging, timeRemaining: pluggedIn ? nil : 3 * 3600)
    }

    /// One energy sample's worth of joules: 20 apps, of which the history keeps the hungriest 15.
    static func joules(for index: Int) -> [BatteryHistory.AppIdentity: Double] {
        var joules: [BatteryHistory.AppIdentity: Double] = [:]
        for offset in 0..<20 {
            let app = apps[(index + offset * 3) % apps.count]
            joules[app] = Double((index * 31 + offset * 17) % 97 + 1) * 3
        }
        return joules
    }

    /// A full day: the level changing every few minutes, a charge in the middle, and an energy sample every five minutes.
    static func fullDay(endingAt end: Date = now) -> BatteryHistory {
        var history = BatteryHistory()
        let start = end.addingTimeInterval(-BatteryHistory.retention)
        var percentage = 100
        var pluggedIn = false
        // A level change every 4 minutes: 360 of them, about the most a day on battery gives.
        for step in 0..<360 {
            let date = start.addingTimeInterval(Double(step) * 240)
            if step == 150 { pluggedIn = true }
            if step == 200 { pluggedIn = false }
            percentage = pluggedIn ? min(percentage + 2, 100) : max(percentage - 1, 5)
            history.record(snapshot(percentage, pluggedIn: pluggedIn), at: date)
        }
        for index in 0..<288 {
            let date = start.addingTimeInterval(Double(index + 1) * 300)
            history.record(joules: joules(for: index), seconds: 300, systemWatts: 8 + Double(index % 5), at: date)
        }
        return history
    }

    /// Readings for the power smoother, like a busy Mac's processes, with some coming and going.
    static func powerReadings(count: Int, round: Int) -> [Int32: Double] {
        var readings: [Int32: Double] = [:]
        readings.reserveCapacity(count)
        for index in 0..<count where (index + round) % 7 != 0 {
            readings[Int32(index + 100)] = Double((index * 13 + round * 7) % 50) / 10
        }
        return readings
    }

    /// An app icon drawn small, as RGBA bytes: a coloured squircle with a white glyph, on transparency.
    static func iconPixels(side: Int = 24) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let center = Double(side - 1) / 2
        for y in 0..<side {
            for x in 0..<side {
                let dx = (Double(x) - center) / center
                let dy = (Double(y) - center) / center
                let index = (y * side + x) * 4
                guard pow(abs(dx), 4) + pow(abs(dy), 4) <= 1 else { continue }
                let isGlyph = abs(dx) < 0.25 && abs(dy) < 0.6
                // Premultiplied, fully opaque: a purple with a gradient, and a white bar.
                let (r, g, b): (Double, Double, Double) = isGlyph ? (1, 1, 1) : (0.55 + 0.2 * dy, 0.25, 0.85 - 0.1 * dx)
                bytes[index] = UInt8(r * 255)
                bytes[index + 1] = UInt8(g * 255)
                bytes[index + 2] = UInt8(b * 255)
                bytes[index + 3] = 255
            }
        }
        return bytes
    }
}

/// A reference type for state a benchmark changes from run to run.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
