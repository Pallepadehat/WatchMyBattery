import Foundation
import Testing

@testable import BatteryKit

struct BatteryHealthTests {
    @Test func parsesSystemProfiler() throws {
        let json = """
            {"SPPowerDataType": [{"_name": "spbattery_information",
              "sppower_battery_health_info": {"sppower_battery_cycle_count": 564,
                "sppower_battery_health": "Good", "sppower_battery_health_maximum_capacity": "88\\u00a0%"}}]}
            """
        let health = try #require(BatteryHealthReader.parse(systemProfilerJSON: Data(json.utf8)))
        #expect(health.condition == .normal)
        #expect(health.cycleCount == 564)
        #expect(abs((health.maximumCapacity ?? 0) - 0.88) < 0.0001)
    }

    @Test func anythingButGoodRecommendsService() throws {
        let json = """
            {"SPPowerDataType": [{"sppower_battery_health_info": {"sppower_battery_health": "Service Recommended"}}]}
            """
        let health = try #require(BatteryHealthReader.parse(systemProfilerJSON: Data(json.utf8)))
        #expect(health.condition == .serviceRecommended)
        #expect(health.maximumCapacity == nil)
    }

    @Test func noBatteryMeansNoHealth() {
        let json = #"{"SPPowerDataType": [{"_name": "sppower_ac_charger_information"}]}"#
        #expect(BatteryHealthReader.parse(systemProfilerJSON: Data(json.utf8)) == nil)
        #expect(BatteryHealthReader.parse(systemProfilerJSON: Data("not json".utf8)) == nil)
    }

    @Test func fallsBackToTheBatteryController() throws {
        let health = try #require(
            BatteryHealthReader.health(fromRegistry: [
                "CycleCount": 564, "BatteryData": ["DesignCapacity": 6249, "NominalChargeCapacity": 5448],
            ]))
        #expect(health.cycleCount == 564)
        #expect(health.condition == nil)
        #expect(abs((health.maximumCapacity ?? 0) - 5448.0 / 6249.0) < 0.0001)
        #expect(BatteryHealthReader.health(fromRegistry: [:]) == nil)
    }
}
