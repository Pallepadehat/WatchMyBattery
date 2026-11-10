import Testing

@testable import BatteryKit

@Suite struct PowerSmootherTests {
    @Test func firstReadingIsTakenAsIs() {
        var smoother = PowerSmoother<Int>(responsiveness: 0.5)
        smoother.add([1: 4])
        #expect(smoother.values[1] == 4)
    }

    @Test func laterReadingsAreAveraged() {
        var smoother = PowerSmoother<Int>(responsiveness: 0.5)
        smoother.add([1: 4])
        smoother.add([1: 8])
        #expect(smoother.values[1] == 6)
    }

    @Test func quietKeysFadeAndAreForgotten() {
        var smoother = PowerSmoother<Int>(responsiveness: 0.5, floor: 0.1)
        smoother.add([1: 0.3])
        smoother.add([:])
        #expect(smoother.values[1] == 0.15)
        smoother.add([:])
        #expect(smoother.values[1] == nil)
    }

    @Test func singleValueSmootherAverages() {
        var smoother = SingleValueSmoother(responsiveness: 0.25)
        smoother.add(20)
        smoother.add(24)
        #expect(smoother.value == 21)
    }
}
