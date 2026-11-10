import Testing

@testable import BatteryKit

@Suite struct TimeFormatTests {
    @Test func clockPadsMinutes() {
        #expect(TimeFormat.clock(4 * 3600 + 50 * 60) == "4:50")
        #expect(TimeFormat.clock(3600 + 5 * 60) == "1:05")
        #expect(TimeFormat.clock(59 * 60) == "0:59")
    }

    @Test func compactUsesMinutesUnderAnHour() {
        #expect(TimeFormat.compact(48 * 60) == "48m")
        #expect(TimeFormat.compact(70 * 60) == "1:10")
    }

    @Test func costAndGainHaveSigns() {
        #expect(TimeFormat.cost(48 * 60) == "\u{2212}48m")
        #expect(TimeFormat.gain(70 * 60) == "+1:10")
    }

    @Test func roundsToTheNearestMinute() {
        #expect(TimeFormat.compact(89) == "1m")
        #expect(TimeFormat.compact(91) == "2m")
    }

    @Test func badValuesBecomeZero() {
        #expect(TimeFormat.clock(-5) == "0:00")
        #expect(TimeFormat.clock(.infinity) == "0:00")
        #expect(TimeFormat.clock(.nan) == "0:00")
    }
}
