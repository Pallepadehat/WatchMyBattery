import Foundation
import Testing

@testable import BatteryKit

/// Accessories as this Mac sees them. With none connected, these only check that reading works and finds nothing odd.
@Suite(.tags(.system))
struct AccessoryReaderSystemTests {
    /// IOKit still exports the functions accessories are read with. If a macOS update removes them, this says so.
    @Test func findsTheAccessoryFunctions() {
        #expect(Symbols.copyPowerSourcesByType != nil)
        #expect(Symbols.accessoryNotification != nil)
    }

    @Test func readsPlausibleAccessories() {
        let accessories = AccessoryReader.read()
        #expect(Set(accessories.map(\.id)).count == accessories.count)
        for accessory in accessories {
            #expect(!accessory.name.isEmpty)
            #expect(!accessory.parts.isEmpty)
            #expect(Set(accessory.parts.map(\.role)).count == accessory.parts.count)
            for part in accessory.parts { #expect((0...100).contains(part.percentage)) }
        }
    }

    /// Every accessory battery `pmset -g accps` lists is one of ours, at the same level.
    @Test func agreesWithPmset() throws {
        let output = try #require(Machine.run("/usr/bin/pmset", ["-g", "accps"]))
        // " -Patrick's AirPods Pro Case (id=58332147)	86%; discharging present: true"
        let listed = output.split(separator: "\n").compactMap { line -> Int? in
            guard !line.contains("InternalBattery"), let match = line.firstMatch(of: /\(id=\d+\)\t(\d+)%;/) else { return nil }
            return Int(match.output.1)
        }
        let ours = AccessoryReader.read().flatMap(\.parts)
        for percentage in listed {
            // pmset shows earbuds as one battery, at the lower of the two; the level can tick over between readings.
            #expect(ours.contains { abs($0.percentage - percentage) <= 1 }, "pmset lists a battery at \(percentage)%")
        }
    }
}
