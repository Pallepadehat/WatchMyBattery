import Testing

@testable import BatteryKit

@Suite struct TimeEstimateTests {
    @Test func quittingAQuarterOfThePowerGivesAThirdMoreTime() {
        // 3 h left at 20 W; removing 5 W leaves 15 W, so 4 h: one hour gained.
        let gained = TimeEstimate.timeGained(timeRemaining: 3 * 3600, systemWatts: 20, appWatts: 5)
        #expect(abs(gained - 3600) < 0.001)
    }

    @Test func nothingGainedWithoutAnEstimateOrPower() {
        #expect(TimeEstimate.timeGained(timeRemaining: 0, systemWatts: 20, appWatts: 5) == 0)
        #expect(TimeEstimate.timeGained(timeRemaining: 3600, systemWatts: 0, appWatts: 5) == 0)
        #expect(TimeEstimate.timeGained(timeRemaining: 3600, systemWatts: 20, appWatts: 0) == 0)
    }

    @Test func anAppCanNeverClaimEverything() {
        let gained = TimeEstimate.timeGained(timeRemaining: 3600, systemWatts: 10, appWatts: 50)
        #expect(gained.isFinite)
        #expect(abs(gained - 3600 * 4) < 0.001)
    }
}
