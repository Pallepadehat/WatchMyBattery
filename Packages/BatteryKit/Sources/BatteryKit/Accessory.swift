import Foundation

/// A Bluetooth accessory with a battery: AirPods and other headphones, a
/// Magic Mouse, Keyboard or Trackpad, a game controller.
///
/// Earbuds come in parts, each with its own battery: the left and right
/// earbuds and the case. Everything else has one.
public struct Accessory: Sendable, Equatable, Identifiable {
    /// What sort of accessory it is, which decides its symbol and how its parts are shown.
    public enum Kind: Int, Sendable, Equatable, Comparable, CaseIterable {
        /// Two earbuds, usually with a case: AirPods, AirPods Pro, Beats earbuds.
        case earbuds
        /// Over-ear or on-ear headphones with one battery: AirPods Max, Beats Studio.
        case headphones
        case keyboard
        case mouse
        case trackpad
        case gameController
        /// An iPhone, read over its cable or Wi‑Fi sync (see ``AppleDeviceReader``).
        case phone
        case tablet
        case watch
        case other

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Headphones of any kind: what the AirPods card is for.
        public var isAudio: Bool { self == .earbuds || self == .headphones }

        /// An iPhone, iPad or Apple Watch: a device of its own rather than an accessory to this Mac.
        public var isDevice: Bool { self == .phone || self == .tablet || self == .watch }
    }

    /// One battery in an accessory.
    public struct Part: Sendable, Equatable, Identifiable {
        public enum Role: Int, Sendable, Equatable, Comparable, CaseIterable {
            case left
            case right
            /// Both earbuds at once, shown as one when they're about the same (see ``Accessory/displayParts``).
            case both
            /// The only battery, in an accessory that has one.
            case single
            case `case`

            public static func < (lhs: Role, rhs: Role) -> Bool { lhs.rawValue < rhs.rawValue }

            /// An earbud, rather than the case or a whole accessory.
            public var isEarbud: Bool { self == .left || self == .right || self == .both }
        }

        public var role: Role
        /// Charge level, 0–100.
        public var percentage: Int
        public var isCharging: Bool

        public var id: Role { role }
        /// The charge level as a fraction, 0–1.
        public var level: Double { Double(percentage) / 100 }

        public init(role: Role, percentage: Int, isCharging: Bool = false) {
            self.role = role
            self.percentage = min(max(percentage, 0), 100)
            self.isCharging = isCharging
        }
    }

    /// Stays the same while the accessory is connected, and across connections where macOS allows.
    public var id: String
    public var name: String
    public var kind: Kind
    /// The parts with a battery, in order: left, right, then the case (or the single battery).
    public var parts: [Part]
    /// The USB or Bluetooth product ID, which tells AirPods models apart.
    public var productID: Int?
    public var vendorID: Int?

    public init(id: String, name: String, kind: Kind, parts: [Part], productID: Int? = nil, vendorID: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parts = parts.sorted { $0.role < $1.role }
        self.productID = productID
        self.vendorID = vendorID
    }

    /// Made by Apple (Beats included).
    public var isApple: Bool { vendorID == Self.appleVendorID }
    static let appleVendorID = 0x004C

    public func part(_ role: Part.Role) -> Part? { parts.first { $0.role == role } }

    /// The parts as the card and the panel show them. Like the iPhone, the
    /// two earbuds become one when they're within a few percent of each other
    /// and charging alike, showing the lower of the two, so a glance isn't
    /// split between two nearly equal numbers.
    public var displayParts: [Part] {
        guard let left = part(.left), let right = part(.right),
            abs(left.percentage - right.percentage) <= Self.mergeTolerance, left.isCharging == right.isCharging
        else { return parts }
        let both = Part(role: .both, percentage: min(left.percentage, right.percentage), isCharging: left.isCharging)
        return [both] + parts.filter { !$0.role.isEarbud }
    }

    /// Earbuds this close are shown as one.
    static let mergeTolerance = 5

    /// The level that decides whether it's running low: the lowest earbud, or
    /// the only battery. The case doesn't count: it's there to charge them.
    /// `nil` when only the case is connected.
    public var lowestLevel: Int? {
        let batteries = parts.filter { $0.role != .case }
        return batteries.map(\.percentage).min()
    }

    /// Something is charging, other than just the case.
    public var isChargingInUse: Bool {
        parts.contains { $0.role != .case && $0.isCharging }
    }
}
