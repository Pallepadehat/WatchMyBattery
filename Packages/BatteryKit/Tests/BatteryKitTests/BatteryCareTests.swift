import Foundation
import Testing

@testable import BatteryKit

/// 0.3.0's battery care: sleeps, what keeps the Mac awake, the "charged to" notification, the battery's readings,
/// exporting the history, and iPhones.
@Suite struct BatteryCareTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sleep(hours: Double, from startLevel: Int, to endLevel: Int, pluggedIn: Bool = false, at offset: TimeInterval = 0)
        -> SleepSession
    {
        let begin = start.addingTimeInterval(offset)
        return SleepSession(
            start: begin, end: begin.addingTimeInterval(hours * 3600), startLevel: startLevel, endLevel: endLevel, wasPluggedIn: pluggedIn)
    }

    // MARK: - Sleep

    @Test func aSleepMeasuresItsDrainPerHour() {
        let night = sleep(hours: 8, from: 80, to: 72)
        #expect(night.used == 8)
        #expect(night.perHour == 1)
        #expect(night.drain == .normal)
        #expect(sleep(hours: 8, from: 80, to: 40).drain == .heavy)
        #expect(sleep(hours: 4, from: 80, to: 72).drain == .elevated)
    }

    @Test func aSleepOnTheAdapterSaysNothingAboutDrain() {
        let night = sleep(hours: 8, from: 60, to: 100, pluggedIn: true)
        #expect(night.used == nil)
        #expect(night.perHour == nil)
        #expect(night.drain == .unknown)
    }

    @Test func aShortSleepHasNoRate() {
        // Two percent in ten minutes would read as 12% an hour: too short to say.
        #expect(sleep(hours: 1 / 6, from: 50, to: 48).perHour == nil)
    }

    @Test func theLogKeepsSleepsInOrderAndDropsTinyOnes() {
        var log = SleepLog()
        do {
            let result = log.record(sleep(hours: 2, from: 90, to: 88, at: 24 * 3600), now: start.addingTimeInterval(30 * 3600))
            #expect(result)
        }
        do {
            let result = log.record(sleep(hours: 8, from: 80, to: 72), now: start.addingTimeInterval(30 * 3600))
            #expect(result)
        }
        do {
            let result = log.record(sleep(hours: 0.001, from: 70, to: 70, at: 3 * 24 * 3600), now: start.addingTimeInterval(30 * 3600))
            #expect(!result)
        }
        #expect(log.sessions.map(\.startLevel) == [80, 90])
        // The same sleep again replaces it.
        log.record(sleep(hours: 8, from: 80, to: 70), now: start.addingTimeInterval(30 * 3600))
        #expect(log.sessions.count == 2)
        #expect(log.sessions.first?.endLevel == 70)
    }

    @Test func theLogLetsGoOfOldSleeps() {
        var log = SleepLog(sessions: [sleep(hours: 8, from: 80, to: 72)])
        log.trim(now: start.addingTimeInterval(SleepLog.retention + 9 * 3600))
        #expect(log.isEmpty)
    }

    @Test func theTypicalRateIsTheMedian() {
        var log = SleepLog()
        #expect(log.typicalPerHour == nil)
        let now = start.addingTimeInterval(10 * 24 * 3600)
        log.record(sleep(hours: 8, from: 80, to: 72, at: 0), now: now)
        log.record(sleep(hours: 8, from: 80, to: 76, at: 24 * 3600), now: now)
        log.record(sleep(hours: 8, from: 80, to: 0, at: 48 * 3600), now: now)
        #expect(log.typicalPerHour == 1)
    }

    @Test func theLogSurvivesTheDisk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sleep-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = SleepLog(sessions: [sleep(hours: 8, from: 80, to: 72)])
        try log.save(to: url)
        #expect(SleepLog.load(from: url) == log)
        #expect(SleepLog.load(from: url.appending(path: "missing")).isEmpty)
    }

    // MARK: - What keeps the Mac awake

    @Test func assertionsLeaveOutMacOSItselfAndAssertionsThatDontKeepItAwake() {
        let assertions = PowerAssertionReader.assertions(from: [
            606: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Powerd - Prevent sleep while display is on", "Process Name": "powerd"]],
            663: [["AssertType": "UserIsActive", "Process Name": "WindowServer", "AssertName": "tickle"]],
            901: [
                [
                    "AssertType": "PreventUserIdleSystemSleep", "AssertName": "caffeinate command-line tool", "Process Name": "caffeinate",
                    "AssertionId": 7, "AssertStartWhen": start,
                ]
            ],
            902: [
                [
                    "AssertionTrueType": "PreventUserIdleDisplaySleep", "AssertType": "NoDisplaySleepAssertion", "AssertName": "Video Wake Lock",
                    "Process Name": "Google Chrome", "AssertionId": 8, "AssertStartWhen": start.addingTimeInterval(60),
                ]
            ],
            903: [["AssertType": "BackgroundTask", "AssertName": "sync", "Process Name": "cloudd"]],
            904: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "released", "Process Name": "Zoom", "AssertLevel": 0]],
        ])
        #expect(assertions.map(\.processName) == ["caffeinate", "Google Chrome"])
        #expect(assertions.map(\.effect) == [.keepsSystemAwake, .keepsDisplayOn])
        #expect(assertions.first?.pid == 901)
    }

    @Test func assertionsHeldForAnAppNameTheApp() {
        let assertions = PowerAssertionReader.assertions(from: [
            800: [
                [
                    "AssertType": "PreventUserIdleSystemSleep", "AssertName": "com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep",
                    "Process Name": "coreaudiod", "AssertionOnBehalfOfPID": 81470, "ResourcesUsed": ["audio-out", "BuiltInSpeakerDevice"],
                ]
            ],
            901: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "caffeinate command-line tool", "Process Name": "caffeinate"]],
        ])
        let audio = assertions.first { $0.pid == 800 }
        #expect(audio?.owner == 81470)
        #expect(audio?.isPlayingAudio == true)
        #expect(audio?.isRecordingAudio == false)
        #expect(assertions.first { $0.pid == 901 }?.owner == 901)
    }

    // MARK: - Charged to a level

    private func charging(_ percentage: Int, pluggedIn: Bool = true) -> BatterySnapshot {
        BatterySnapshot(
            percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery, chargeState: pluggedIn ? .charging : .discharging,
            timeRemaining: nil)
    }

    @Test func chargingToTheTargetNotifiesOnce() {
        var alert = ChargeLevelAlert()
        do {
            let result = alert.update(with: charging(70), target: 80)
            #expect(!result)
        }
        do {
            let result = alert.update(with: charging(79), target: 80)
            #expect(!result)
        }
        do {
            let result = alert.update(with: charging(80), target: 80)
            #expect(result)
        }
        do {
            let result = alert.update(with: charging(81), target: 80)
            #expect(!result)
        }
        // Unplugged and plugged in again below it: once more.
        do {
            let result = alert.update(with: charging(78, pluggedIn: false), target: 80)
            #expect(!result)
        }
        do {
            let result = alert.update(with: charging(78), target: 80)
            #expect(!result)
        }
        do {
            let result = alert.update(with: charging(80), target: 80)
            #expect(result)
        }
    }

    @Test func pluggingInAboveTheTargetSaysNothing() {
        var alert = ChargeLevelAlert()
        do {
            let result = alert.update(with: charging(50, pluggedIn: false), target: 80)
            #expect(!result)
        }
        do {
            let result = alert.update(with: charging(85), target: 80)
            #expect(!result)
        }
        do {
            let result = alert.update(with: charging(90), target: 80)
            #expect(!result)
        }
    }

    @Test func aMacWithoutABatteryIsNeverCharged() {
        var alert = ChargeLevelAlert()
        do {
            let result = alert.update(with: .noBattery, target: 80)
            #expect(!result)
        }
        do {
            let result = alert.update(with: .noBattery, target: 80)
            #expect(!result)
        }
    }

    // MARK: - Readings

    @Test func readingsComeFromTheRegistryInMilliUnits() {
        let readings = BatteryReadingsReader.readings(fromRegistry: ["Voltage": 11_240, "InstantAmperage": -1106, "Temperature": 3050])
        #expect(readings.voltage == 11.24)
        #expect(readings.current == -1.106)
        #expect(readings.temperature == 30.5)
        #expect(readings.batteryWatts.map { ($0 * 100).rounded() / 100 } == -12.43)
        #expect(readings.warmth == .normal)
    }

    @Test func implausibleTemperaturesAreIgnored() {
        #expect(BatteryReadingsReader.readings(fromRegistry: ["Temperature": 65_535]).temperature == nil)
        #expect(BatteryReadingsReader.temperature(fromSMC: [21.8, 21.5, 400]) == 21.65)
        #expect(BatteryReadingsReader.temperature(fromSMC: []) == nil)
    }

    @Test func warmthFollowsTheTemperature() {
        #expect(BatteryReadings(temperature: 36).warmth == .warm)
        #expect(BatteryReadings(temperature: 42).warmth == .hot)
        #expect(BatteryReadings().warmth == nil)
    }

    @Test func smallWobblesDontCountAsChanges() {
        let base = BatteryReadings(temperature: 30, voltage: 11.2, current: -1)
        #expect(!base.differsVisibly(from: BatteryReadings(temperature: 30.2, voltage: 11.21, current: -1.01)))
        #expect(base.differsVisibly(from: BatteryReadings(temperature: 31, voltage: 11.2, current: -1)))
        #expect(base.differsVisibly(from: BatteryReadings(temperature: nil, voltage: 11.2, current: -1)))
    }

    // MARK: - Export

    @Test func csvQuotesWhatItHasTo() {
        #expect(HistoryExport.escaped("Xcode") == "Xcode")
        #expect(HistoryExport.escaped("Figma, Inc") == "\"Figma, Inc\"")
        #expect(HistoryExport.escaped("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func csvHasARowPerHour() {
        var profile = UsageProfile()
        let app = BatteryHistory.AppIdentity(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        profile.record(level: .init(date: start, percentage: 90, isPluggedIn: false))
        profile.record(
            BatteryHistory.EnergySample(date: start.addingTimeInterval(600), seconds: 600, joules: [app.key: 3600], systemWatts: 10),
            apps: [app.key: app])
        profile.record(level: .init(date: start.addingTimeInterval(600), percentage: 88, isPluggedIn: false))
        let lines = HistoryExport.csv(profile: profile).split(separator: "\n")
        #expect(lines.count == 1 + profile.hours.count)
        #expect(lines.first?.hasPrefix("hour_start,") == true)
        #expect(lines.last?.contains("Xcode: 1.00") == true)
    }

    @Test func jsonHasEverything() throws {
        let data = try HistoryExport.json(
            history: BatteryHistory(), profile: UsageProfile(), sleeps: SleepLog(sessions: [sleep(hours: 8, from: 80, to: 72)]), now: start)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["exported", "format", "apps", "hours", "levels", "samples", "sleeps"])
        #expect((object["sleeps"] as? [[String: Any]])?.first?["percentPerHour"] as? Double == 1)
    }

    // MARK: - Keeping the history longer

    @Test func aLongerRetentionKeepsOlderHours() {
        let now = start.addingTimeInterval(40 * 24 * 3600)
        let old = UsageProfile.Hour(
            start: UsageProfile.hourStart(of: start), batterySeconds: 3600, drained: 10, sampledSeconds: 0, systemJoules: 0,
            measuredSeconds: 0, appJoules: [:])
        let twoWeeks = UsageProfile(hours: [old], apps: [:], lastLevel: nil, now: now)
        #expect(twoWeeks.isEmpty)
        var ninety = UsageProfile(hours: [old], apps: [:], lastLevel: nil, now: now, retention: 90 * 24 * 3600)
        #expect(ninety.hours.count == 1)
        ninety.retention = UsageProfile.retention
        ninety.trim(now: now)
        #expect(ninety.isEmpty)
    }

    // MARK: - iPhone

    @Test func anIPhoneBecomesAnAccessory() throws {
        let phone = try #require(
            AppleDeviceReader.accessory(
                id: "abc",
                values: ["DeviceName": "Patrick's iPhone", "DeviceClass": "iPhone", "BatteryCurrentCapacity": 64, "BatteryIsCharging": true]))
        #expect(phone.kind == .phone)
        #expect(phone.kind.isDevice)
        #expect(phone.parts == [Accessory.Part(role: .single, percentage: 64, isCharging: true)])
        #expect(phone.id == "device:abc")
        let pad = AppleDeviceReader.accessory(id: "p", values: ["ProductType": "iPad14,1", "BatteryCurrentCapacity": 20])
        #expect(pad?.kind == .tablet)
        #expect(pad?.name == "iPad")
        #expect(AppleDeviceReader.accessory(id: "x", values: ["DeviceName": "Locked"]) == nil)
    }
}
