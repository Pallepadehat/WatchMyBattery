import Foundation
import Testing

@testable import BatteryKit

/// What IOPowerSources publishes for a pair of AirPods Pro: the case on its
/// own, and the earbuds as one "Combined" battery with each earbud inside.
private func airPods(left: Int = 80, right: Int = 80, case casePercentage: Int? = 86, charging: Bool = false) -> [[String: Any]] {
    func earbud(_ side: String, _ percentage: Int) -> [String: Any] {
        [
            "Type": "Accessory Source", "Accessory Category": "Headset", "Group Identifier": "group-1",
            "Accessory Identifier": "buds-1", "Part Identifier": side, "Name": "Patrick’s AirPods Pro",
            "Current Capacity": percentage, "Max Capacity": 100, "Is Charging": charging, "Is Present": true,
            "Product ID": 0x2027, "Vendor ID": 76,
        ]
    }
    var descriptions: [[String: Any]] = [
        [
            "Type": "Accessory Source", "Accessory Category": "Headset", "Group Identifier": "group-1",
            "Accessory Identifier": "buds-1", "Part Identifier": "Combined", "Name": "Patrick’s AirPods Pro",
            "Current Capacity": min(left, right), "Max Capacity": 100, "Is Charging": charging, "Is Present": true,
            "Product ID": 0x2027, "Vendor ID": 76,
            "Combined Parts": [earbud("Left", left), earbud("Right", right)],
        ]
    ]
    if let casePercentage {
        descriptions.insert(
            [
                "Type": "Accessory Source", "Accessory Category": "Audio Battery Case", "Group Identifier": "group-1",
                "Accessory Identifier": "case-1", "Part Identifier": "Case", "Name": "Patrick’s AirPods Pro Case",
                "Current Capacity": casePercentage, "Max Capacity": 100, "Is Charging": false, "Is Present": true,
                "Product ID": 0x2027, "Vendor ID": 76,
            ], at: 0)
    }
    return descriptions
}

private func magicMouse(_ percentage: Int, flags: Int = 0, address: String = "aa-bb") -> [String: Any] {
    ["Product": "Magic Mouse", "BatteryPercent": percentage, "BatteryStatusFlags": flags, "DeviceAddress": address, "VendorID": 76]
}

struct AccessoryReaderTests {
    @Test func joinsTheEarbudsAndTheirCaseIntoOneAccessory() throws {
        let accessories = AccessoryReader.accessories(fromPowerSources: airPods(left: 72, right: 80, case: 86, charging: true))
        let airPods = try #require(accessories.only)
        #expect(airPods.id == "group-1")
        #expect(airPods.name == "Patrick’s AirPods Pro")
        #expect(airPods.kind == .earbuds)
        #expect(airPods.productID == 0x2027)
        #expect(airPods.isApple)
        #expect(airPods.parts.map(\.role) == [.left, .right, .case])
        #expect(airPods.parts.map(\.percentage) == [72, 80, 86])
        #expect(airPods.part(.left)?.isCharging == true)
        #expect(airPods.part(.case)?.isCharging == false)
    }

    @Test func aCaseOnItsOwnIsNamedAfterItsEarbuds() throws {
        var descriptions = airPods()
        descriptions.removeLast()
        let accessory = try #require(AccessoryReader.accessories(fromPowerSources: descriptions).only)
        #expect(accessory.name == "Patrick’s AirPods Pro")
        #expect(accessory.kind == .earbuds)
        #expect(accessory.parts.map(\.role) == [.case])
        #expect(accessory.lowestLevel == nil)
    }

    @Test func headphonesWithOneBattery() throws {
        let max: [String: Any] = [
            "Type": "Accessory Source", "Accessory Category": "Headphones", "Accessory Identifier": "max-1",
            "Name": "AirPods Max", "Current Capacity": 41, "Max Capacity": 100, "Is Charging": false,
        ]
        let accessory = try #require(AccessoryReader.accessories(fromPowerSources: [max]).only)
        #expect(accessory.id == "max-1")
        #expect(accessory.kind == .headphones)
        #expect(accessory.parts == [Accessory.Part(role: .single, percentage: 41)])
    }

    @Test func skipsWhatIsntAnAccessoryOrIsntThere() {
        let battery: [String: Any] = ["Type": "InternalBattery", "Name": "InternalBattery-0", "Current Capacity": 90, "Max Capacity": 100]
        var gone = airPods(case: nil)[0]
        gone["Is Present"] = false
        #expect(AccessoryReader.accessories(fromPowerSources: [battery, gone]).isEmpty)
    }

    @Test func scalesToMaxCapacity() throws {
        let description: [String: Any] = [
            "Type": "Accessory Source", "Name": "Controller", "Accessory Category": "Game Controller",
            "Current Capacity": 1200, "Max Capacity": 1600,
        ]
        let accessory = try #require(AccessoryReader.accessories(fromPowerSources: [description]).only)
        #expect(accessory.parts.first?.percentage == 75)
        #expect(accessory.kind == .gameController)
    }

    @Test func readsMagicAccessoriesFromTheRegistry() throws {
        let entries = [
            magicMouse(64), magicMouse(64),
            ["Product": "Magic Keyboard with Touch ID", "BatteryPercent": 12, "BatteryStatusFlags": 3, "DeviceAddress": "cc"],
            ["Product": "Magic Trackpad", "DeviceAddress": "dd"],
        ]
        let accessories = AccessoryReader.accessories(fromRegistry: entries)
        // One per device, and none without a battery level.
        #expect(accessories.map(\.name) == ["Magic Mouse", "Magic Keyboard with Touch ID"])
        #expect(accessories.map(\.kind) == [.mouse, .keyboard])
        #expect(accessories[0].parts == [Accessory.Part(role: .single, percentage: 64)])
        #expect(accessories[1].parts == [Accessory.Part(role: .single, percentage: 12, isCharging: true)])
    }

    @Test func aLevelOfZeroIsntReadYet() {
        #expect(AccessoryReader.accessories(fromRegistry: [magicMouse(0)]).isEmpty)
    }

    @Test func theSameAppleProductUnderAnotherNameIsListedOnce() {
        let fromPowerSources = Accessory(
            id: "ps", name: "Patrick’s Magic Keyboard", kind: .keyboard, parts: [.init(role: .single, percentage: 60)], productID: 0x029C,
            vendorID: 0x004C)
        let registry = AccessoryReader.accessories(fromRegistry: [
            ["Product": "Magic Keyboard with Touch ID", "BatteryPercent": 61, "DeviceAddress": "kb", "ProductID": 0x029C, "VendorID": 76],
            ["Product": "Magic Mouse", "BatteryPercent": 40, "DeviceAddress": "m", "ProductID": 0x0269, "VendorID": 76],
        ])
        #expect(AccessoryReader.merge(powerSources: [fromPowerSources], registry: registry).map(\.id) == ["ps", "hid:m"])
    }

    @Test func listsADeviceBothSourcesKnowOnce() {
        let fromPowerSources = Accessory(id: "ps", name: "Magic Mouse", kind: .mouse, parts: [.init(role: .single, percentage: 60)])
        let registry = AccessoryReader.accessories(fromRegistry: [
            magicMouse(61), ["Product": "Magic Keyboard", "BatteryPercent": 50, "DeviceAddress": "kb"],
        ])
        let airPods = AccessoryReader.accessories(fromPowerSources: airPods())
        let merged = AccessoryReader.merge(powerSources: [fromPowerSources] + airPods, registry: registry)
        // Headphones first, then the rest by kind.
        #expect(merged.map(\.id) == ["group-1", "hid:kb", "ps"])
    }
}

struct AccessoryTests {
    @Test func earbudsAboutTheSameAreShownAsOne() {
        let accessory = Accessory(
            id: "a", name: "AirPods", kind: .earbuds,
            parts: [.init(role: .case, percentage: 50), .init(role: .right, percentage: 81), .init(role: .left, percentage: 78)])
        #expect(accessory.displayParts == [.init(role: .both, percentage: 78), .init(role: .case, percentage: 50)])
    }

    @Test func earbudsFarApartOrChargingDifferentlyStaySeparate() {
        let apart = Accessory(
            id: "a", name: "AirPods", kind: .earbuds, parts: [.init(role: .left, percentage: 40), .init(role: .right, percentage: 81)])
        #expect(apart.displayParts.map(\.role) == [.left, .right])
        let oneCharging = Accessory(
            id: "a", name: "AirPods", kind: .earbuds,
            parts: [.init(role: .left, percentage: 80, isCharging: true), .init(role: .right, percentage: 80)])
        #expect(oneCharging.displayParts.map(\.role) == [.left, .right])
    }

    @Test func theLowestLevelLeavesOutTheCase() {
        let accessory = Accessory(
            id: "a", name: "AirPods", kind: .earbuds,
            parts: [.init(role: .left, percentage: 30), .init(role: .right, percentage: 18), .init(role: .case, percentage: 5, isCharging: true)])
        #expect(accessory.lowestLevel == 18)
        #expect(!accessory.isChargingInUse)
    }
}

struct AccessoryArrivalsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func buds(_ id: String = "buds", parts: [Accessory.Part.Role] = [.left, .right, .case]) -> Accessory {
        Accessory(id: id, name: "AirPods", kind: .earbuds, parts: parts.map { .init(role: $0, percentage: 80) })
    }

    @Test func whatsConnectedAtLaunchDoesntCount() {
        var arrivals = AccessoryArrivals()
        #expect(arrivals.update(with: [buds()], at: start).isEmpty)
        #expect(arrivals.update(with: [buds()], at: start.addingTimeInterval(5)).isEmpty)
    }

    @Test func headphonesConnectingArrive() {
        var arrivals = AccessoryArrivals()
        _ = arrivals.update(with: [], at: start)
        #expect(arrivals.update(with: [buds()], at: start.addingTimeInterval(10)).map(\.id) == ["buds"])
        // Once.
        #expect(arrivals.update(with: [buds()], at: start.addingTimeInterval(20)).isEmpty)
    }

    @Test func aMouseOrALoneCaseIsNoArrival() {
        var arrivals = AccessoryArrivals()
        _ = arrivals.update(with: [], at: start)
        let mouse = Accessory(id: "mouse", name: "Magic Mouse", kind: .mouse, parts: [.init(role: .single, percentage: 50)])
        #expect(arrivals.update(with: [mouse, buds(parts: [.case])], at: start.addingTimeInterval(5)).isEmpty)
        // The earbuds join their case: now they've arrived.
        #expect(arrivals.update(with: [mouse, buds()], at: start.addingTimeInterval(9)).map(\.id) == ["buds"])
    }

    @Test func droppingOutBrieflyIsntANewArrival() {
        var arrivals = AccessoryArrivals(cooldown: 60)
        _ = arrivals.update(with: [], at: start)
        _ = arrivals.update(with: [buds()], at: start.addingTimeInterval(1))
        _ = arrivals.update(with: [], at: start.addingTimeInterval(100))
        #expect(arrivals.update(with: [buds()], at: start.addingTimeInterval(130)).isEmpty)
        _ = arrivals.update(with: [], at: start.addingTimeInterval(200))
        #expect(arrivals.update(with: [buds()], at: start.addingTimeInterval(300)).map(\.id) == ["buds"])
    }
}

struct AccessoryLowBatteryAlertTests {
    private func mouse(_ percentage: Int, charging: Bool = false) -> Accessory {
        Accessory(id: "mouse", name: "Magic Mouse", kind: .mouse, parts: [.init(role: .single, percentage: percentage, isCharging: charging)])
    }

    @Test func notifiesOnceWhenItRunsLow() {
        var alert = AccessoryLowBatteryAlert()
        #expect(alert.update(with: [mouse(40)], threshold: 20).isEmpty)
        #expect(alert.update(with: [mouse(20)], threshold: 20).map(\.id) == ["mouse"])
        #expect(alert.update(with: [mouse(12)], threshold: 20).isEmpty)
    }

    @Test func chargingRearmsIt() {
        var alert = AccessoryLowBatteryAlert()
        _ = alert.update(with: [mouse(15)], threshold: 20)
        _ = alert.update(with: [mouse(16, charging: true)], threshold: 20)
        #expect(alert.notified.isEmpty)
        #expect(alert.update(with: [mouse(17)], threshold: 20).map(\.id) == ["mouse"])
    }

    @Test func aWobbleAroundTheThresholdDoesntNotifyTwice() {
        var alert = AccessoryLowBatteryAlert()
        _ = alert.update(with: [mouse(20)], threshold: 20)
        _ = alert.update(with: [mouse(23)], threshold: 20)
        #expect(alert.update(with: [mouse(20)], threshold: 20).isEmpty)
        // Clearly above it, then low again: that's worth hearing about.
        _ = alert.update(with: [mouse(40)], threshold: 20)
        #expect(alert.update(with: [mouse(19)], threshold: 20).map(\.id) == ["mouse"])
    }

    @Test func earbudsGoByTheLowerOneAndIgnoreTheCase() {
        var alert = AccessoryLowBatteryAlert()
        let buds = Accessory(
            id: "buds", name: "AirPods", kind: .earbuds,
            parts: [.init(role: .left, percentage: 35), .init(role: .right, percentage: 19), .init(role: .case, percentage: 3)])
        #expect(alert.update(with: [buds], threshold: 20).map(\.id) == ["buds"])
        let caseOnly = Accessory(id: "case", name: "AirPods", kind: .earbuds, parts: [.init(role: .case, percentage: 3)])
        #expect(alert.update(with: [caseOnly], threshold: 20).isEmpty)
    }
}

extension Array {
    /// The only element, or `nil` when there are none or several.
    fileprivate var only: Element? { count == 1 ? first : nil }
}

struct AccessoryModelTests {
    private func accessory(_ name: String, kind: Accessory.Kind = .earbuds, productID: Int? = nil, apple: Bool = true) -> Accessory {
        Accessory(
            id: "x", name: name, kind: kind, parts: [.init(role: .single, percentage: 50)], productID: productID,
            vendorID: apple ? 0x004C : 0x1234)
    }

    @Test func knowsAppleModelsByProductID() {
        let pro = accessory("Patrick’s AirPods Pro", productID: 0x2014)
        #expect(pro.model == AccessoryModel(family: .airPodsPro, name: "AirPods Pro 2"))
        #expect(pro.modelSubtitle == "AirPods Pro 2")
        #expect(accessory("Studio", kind: .headphones, productID: 0x2017).model?.family == .beatsHeadphones)
        // Someone else's product ID means nothing.
        #expect(accessory("Gadget", productID: 0x2014, apple: false).model == nil)
    }

    @Test func fallsBackToTheName() {
        #expect(accessory("Patrick’s AirPods Pro").model == AccessoryModel(family: .airPodsPro))
        #expect(accessory("AirPods", kind: .headphones).model?.family == .airPodsMax)
        #expect(accessory("Magic Keyboard with Touch ID", kind: .keyboard).model?.family == .magicKeyboard)
        #expect(accessory("Beats Studio Buds +").model?.family == .studioBudsPlus)
        #expect(accessory("Xbox Wireless Controller", kind: .gameController).model == nil)
    }

    @Test func theSubtitleIsOnlyThereWhenTheNameDoesntSayIt() {
        #expect(accessory("AirPods Pro 3", productID: 0x2027).modelSubtitle == nil)
        #expect(accessory("Patrick’s AirPods Pro 3", productID: 0x2027).modelSubtitle == nil)
        #expect(accessory("Patrick’s Buds", productID: 0x2027).modelSubtitle == "AirPods Pro 3")
        // Only the family is known: nothing to add.
        #expect(accessory("Patrick’s Buds").modelSubtitle == nil)
    }
}
