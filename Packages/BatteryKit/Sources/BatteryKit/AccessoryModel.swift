import Foundation

/// Which Apple accessory this is, as precisely as can be told: AirPods Pro 2
/// rather than just "earbuds". It decides the symbols the card and the panel
/// draw, and the model name under a renamed accessory ("Patrick's Buds",
/// AirPods Pro 2).
///
/// AirPods and Beats are told apart by their Bluetooth product ID, and the
/// Magic accessories by the name they report. An accessory nobody here
/// recognises still shows, with a symbol for its kind.
public struct AccessoryModel: Sendable, Equatable {
    /// Models drawn alike: the same symbols fit all of them.
    public enum Family: Sendable, Equatable, CaseIterable {
        case airPods, airPods3, airPods4, airPodsPro, airPodsMax
        case powerbeats, powerbeatsPro, fitPro, studioBuds, studioBudsPlus, soloBuds, beatsEarphones
        case beatsHeadphones, beatsPill
        case magicMouse, magicKeyboard, magicTrackpad
    }

    public var family: Family
    /// "AirPods Pro 2"; `nil` when only the family is known.
    public var name: String?

    public init(family: Family, name: String? = nil) {
        self.family = family
        self.name = name
    }

    /// Recognises an accessory, or returns `nil`.
    public init?(_ accessory: Accessory) {
        if accessory.isApple, let productID = accessory.productID, let known = Self.byProductID[productID] {
            self = known
            return
        }
        guard let family = Self.family(fromName: accessory.name, kind: accessory.kind) else { return nil }
        self.init(family: family)
    }

    /// From the name, which is the model's own until the owner renames it ("Patrick's AirPods Pro").
    static func family(fromName name: String, kind: Accessory.Kind) -> Family? {
        let name = name.lowercased()
        let rules: [(String, Family)] = [
            ("airpods pro", .airPodsPro), ("airpods max", .airPodsMax), ("airpods 4", .airPods4), ("airpods (4", .airPods4),
            ("airpods 3", .airPods3), ("airpods (3", .airPods3),
            ("powerbeats pro", .powerbeatsPro), ("powerbeats", .powerbeats), ("fit pro", .fitPro),
            ("studio buds +", .studioBudsPlus), ("studio buds+", .studioBudsPlus), ("studio buds", .studioBuds),
            ("solo buds", .soloBuds), ("beats flex", .beatsEarphones), ("beatsx", .beatsEarphones), ("beats pill", .beatsPill),
            ("magic mouse", .magicMouse), ("magic keyboard", .magicKeyboard), ("magic trackpad", .magicTrackpad),
        ]
        if let family = rules.first(where: { name.contains($0.0) })?.1 { return family }
        if name.contains("airpods") { return kind == .headphones ? .airPodsMax : .airPods }
        if name.contains("beats") { return kind == .earbuds ? .studioBuds : .beatsHeadphones }
        return nil
    }

    /// Apple's Bluetooth product IDs for AirPods and Beats.
    static let byProductID: [Int: AccessoryModel] = [
        0x2002: .init(family: .airPods, name: "AirPods"),
        0x200F: .init(family: .airPods, name: "AirPods (2nd generation)"),
        0x2013: .init(family: .airPods3, name: "AirPods (3rd generation)"),
        0x2019: .init(family: .airPods4, name: "AirPods 4"),
        0x201B: .init(family: .airPods4, name: "AirPods 4 with Active Noise Cancellation"),
        0x200E: .init(family: .airPodsPro, name: "AirPods Pro"),
        0x2014: .init(family: .airPodsPro, name: "AirPods Pro 2"),
        0x2024: .init(family: .airPodsPro, name: "AirPods Pro 2"),
        0x2027: .init(family: .airPodsPro, name: "AirPods Pro 3"),
        0x200A: .init(family: .airPodsMax, name: "AirPods Max"),
        0x201F: .init(family: .airPodsMax, name: "AirPods Max"),
        0x2003: .init(family: .powerbeats, name: "Powerbeats3"),
        0x200D: .init(family: .powerbeats, name: "Powerbeats"),
        0x200B: .init(family: .powerbeatsPro, name: "Powerbeats Pro"),
        0x201D: .init(family: .powerbeatsPro, name: "Powerbeats Pro 2"),
        0x2012: .init(family: .fitPro, name: "Beats Fit Pro"),
        0x2011: .init(family: .studioBuds, name: "Beats Studio Buds"),
        0x2016: .init(family: .studioBudsPlus, name: "Beats Studio Buds +"),
        0x2026: .init(family: .soloBuds, name: "Beats Solo Buds"),
        0x2005: .init(family: .beatsEarphones, name: "BeatsX"),
        0x2010: .init(family: .beatsEarphones, name: "Beats Flex"),
        0x2006: .init(family: .beatsHeadphones, name: "Beats Solo3"),
        0x200C: .init(family: .beatsHeadphones, name: "Beats Solo Pro"),
        0x2025: .init(family: .beatsHeadphones, name: "Beats Solo 4"),
        0x2009: .init(family: .beatsHeadphones, name: "Beats Studio3"),
        0x2017: .init(family: .beatsHeadphones, name: "Beats Studio Pro"),
    ]
}

extension Accessory {
    /// The Apple model, when it's one this knows.
    public var model: AccessoryModel? { AccessoryModel(self) }

    /// The model's name, when the accessory's own name doesn't already end in
    /// it: "AirPods Pro 3" under "Patrick's AirPods Pro" or "Patrick's Buds",
    /// but nothing under "AirPods Pro 3".
    public var modelSubtitle: String? {
        guard let modelName = model?.name else { return nil }
        let simplified = { (text: String) in text.lowercased().replacingOccurrences(of: "’", with: "'") }
        return simplified(name).hasSuffix(simplified(modelName)) ? nil : modelName
    }
}
