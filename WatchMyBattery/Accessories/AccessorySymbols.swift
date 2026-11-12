import AppKit
import BatteryKit
import SwiftUI

/// The SF Symbols for an accessory and its parts.
///
/// Every Apple model gets its own (AirPods Pro get AirPods Pro, Beats Fit
/// Pro get Beats Fit Pro), and anything else one for its kind. Newer symbols
/// fall back to older ones on macOS versions that don't have them.
struct AccessorySymbols {
    let device: String
    let left: String
    let right: String
    let `case`: String

    func symbol(for role: Accessory.Part.Role) -> String {
        switch role {
        case .left: left
        case .right: right
        case .both, .single: device
        case .case: self.case
        }
    }

    init(_ accessory: Accessory) {
        if let family = accessory.model?.family {
            self.init(family)
            return
        }
        switch accessory.kind {
        case .earbuds:
            self.init("earbuds", Self.first("earbud.left", "earbuds"), Self.first("earbud.right", "earbuds"), "earbuds.case.fill")
        case .headphones: self.init("headphones")
        case .keyboard: self.init("keyboard.fill")
        case .mouse: self.init(Self.first("magicmouse.fill", "computermouse.fill"))
        case .trackpad: self.init("rectangle.and.hand.point.up.left.fill")
        case .gameController: self.init("gamecontroller.fill")
        case .other: self.init("battery.100percent")
        }
    }

    private init(_ family: AccessoryModel.Family) {
        switch family {
        case .airPods:
            self.init("airpods", "airpod.left", "airpod.right", "airpods.chargingcase.fill")
        case .airPods3:
            self.init("airpods.gen3", "airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless.fill")
        case .airPods4:
            self.init(
                Self.first("airpods.gen4", "airpods.gen3"), Self.first("airpods.gen4.left", "airpod.gen3.left"),
                Self.first("airpods.gen4.right", "airpod.gen3.right"),
                Self.first("airpods.gen4.chargingcase.wireless.fill", "airpods.gen3.chargingcase.wireless.fill"))
        case .airPodsPro:
            self.init("airpodspro", "airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless.fill")
        case .airPodsMax:
            self.init("airpodsmax")
        case .powerbeats:
            self.init(
                Self.first("beats.powerbeats", "beats.earphones"), Self.first("beats.powerbeats.left", "beats.earphones"),
                Self.first("beats.powerbeats.right", "beats.earphones"))
        case .powerbeatsPro:
            self.init("beats.powerbeatspro", "beats.powerbeatspro.left", "beats.powerbeatspro.right", "beats.powerbeatspro.chargingcase.fill")
        case .fitPro:
            self.init("beats.fitpro", "beats.fitpro.left", "beats.fitpro.right", "beats.fitpro.chargingcase.fill")
        case .studioBuds:
            self.init("beats.studiobuds", "beats.studiobuds.left", "beats.studiobuds.right", "beats.studiobuds.chargingcase.fill")
        case .studioBudsPlus:
            self.init(
                Self.first("beats.studiobudsplus", "beats.studiobuds"), Self.first("beats.studiobudsplus.left", "beats.studiobuds.left"),
                Self.first("beats.studiobudsplus.right", "beats.studiobuds.right"),
                Self.first("beats.studiobudsplus.chargingcase.fill", "beats.studiobuds.chargingcase.fill"))
        case .soloBuds:
            self.init(
                Self.first("beats.solobuds", "beats.studiobuds"), Self.first("beats.solobuds.left", "beats.studiobuds.left"),
                Self.first("beats.solobuds.right", "beats.studiobuds.right"),
                Self.first("beats.solobuds.chargingcase.fill", "beats.studiobuds.chargingcase.fill"))
        case .beatsEarphones:
            self.init("beats.earphones")
        case .beatsHeadphones:
            self.init("beats.headphones")
        case .beatsPill:
            self.init(Self.first("beats.pill.fill", "hifispeaker.fill"))
        case .magicMouse:
            self.init(Self.first("magicmouse.fill", "computermouse.fill"))
        case .magicKeyboard:
            self.init("keyboard.fill")
        case .magicTrackpad:
            self.init("rectangle.and.hand.point.up.left.fill")
        }
    }

    private init(_ device: String, _ left: String? = nil, _ right: String? = nil, _ case: String? = nil) {
        self.device = device
        self.left = left ?? device
        self.right = right ?? device
        self.case = `case` ?? device
    }

    /// The first symbol this macOS has.
    private static func first(_ names: String...) -> String {
        names.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? names.last!
    }
}

extension Accessory {
    var symbols: AccessorySymbols { AccessorySymbols(self) }
}

extension Accessory.Part {
    /// At or below this, a level shows in red, like the iPhone's battery widget.
    static let lowPercentage = 20

    var isLow: Bool { percentage <= Self.lowPercentage && !isCharging }

    /// "Left", "Right", "Case"; nothing for an accessory's only battery.
    var title: LocalizedStringKey? {
        switch role {
        case .left: "Left"
        case .right: "Right"
        case .both: "Earbuds"
        case .case: "Case"
        case .single: nil
        }
    }

    /// For VoiceOver and notifications: "Left 80%", or just "80%".
    var spokenDescription: String {
        let level = level.formatted(.percent.precision(.fractionLength(0)))
        let charging = isCharging ? String(localized: ", charging") : ""
        switch role {
        case .left: return String(localized: "Left \(level)") + charging
        case .right: return String(localized: "Right \(level)") + charging
        case .both: return String(localized: "Earbuds \(level)") + charging
        case .case: return String(localized: "Case \(level)") + charging
        case .single: return level + charging
        }
    }
}

/// Green while there's charge to spare or it's charging, orange getting low, red when low: like the iPhone's battery widget.
enum AccessoryColor {
    static let green = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let orange = Color(red: 1, green: 0.62, blue: 0.04)
    static let red = Color(red: 0.95, green: 0.27, blue: 0.23)

    static func of(_ part: Accessory.Part) -> Color {
        if part.isCharging { return green }
        if part.percentage <= Accessory.Part.lowPercentage { return red }
        if part.percentage <= 30 { return orange }
        return green
    }
}

/// A ring that fills up with a battery's level: a sweep of colour that
/// deepens towards its end, and, while charging, a soft glow that breathes.
struct LevelRing: View {
    /// 0–1. Animatable, so the ring can fill up as the card appears.
    let level: Double
    let color: Color
    let lineWidth: CGFloat
    var isCharging = false
    /// Tint the inside of the ring, for the card's larger rings.
    var fillsCenter = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if fillsCenter {
                Circle()
                    .fill(color.opacity(0.08))
                    .padding(lineWidth)
            }
            Circle()
                .stroke(.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(level, 0.001))
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.62), color], center: .center, startAngle: .degrees(0),
                        endAngle: .degrees(max(360 * level, 1))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .modifier(RingGlow(color: color, isOn: isCharging && !reduceMotion, radius: lineWidth * 0.9))
        }
        .padding(lineWidth / 2)
    }
}

/// A glow around a charging ring that swells and fades, slowly.
private struct RingGlow: ViewModifier {
    let color: Color
    let isOn: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if isOn {
            content.phaseAnimator([false, true]) { view, bright in
                view.shadow(color: color.opacity(bright ? 0.65 : 0.15), radius: bright ? radius * 1.6 : radius * 0.6)
            } animation: { _ in
                .easeInOut(duration: 1.6)
            }
        } else {
            content
        }
    }
}
