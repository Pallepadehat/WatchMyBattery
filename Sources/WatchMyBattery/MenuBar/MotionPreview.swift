import BatteryKit
import SwiftUI

/// The menu bar's battery playing a motion, larger, for choosing one: in the onboarding and wherever else it helps
/// to see a style before picking it. It's the menu bar's own drawing (``BatteryIcon``) at the motion's own frames
/// and timing (``MenuBarMotion/cycle``), so it looks exactly as it will up there.
struct MotionPreview: View {
    let snapshot: BatterySnapshot
    let motion: MenuBarMotion?
    var style: MenuBarIconStyle = .battery
    var usesColor = true
    /// How much larger than in the menu bar.
    var scale: CGFloat = 2.5

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: motion == nil || reduceMotion)) { timeline in
            let phase = motion.flatMap { Self.phase(of: $0.cycle, at: timeline.date) }
            let image = icon(phase: phase).image()
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: BatteryIcon.imageHeight * scale)
        }
        .accessibilityHidden(true)
    }

    private func icon(phase: Double?) -> BatteryIcon {
        var icon = BatteryIcon(snapshot: snapshot, style: style, usesColor: usesColor, drawsForDarkBar: colorScheme == .dark)
        icon.motion = phase == nil ? nil : motion
        icon.animationPhase = phase
        return icon
    }

    /// The frame showing at `date`, as the menu bar's timer would show it: its phase, or `nil` while it rests.
    static func phase(of cycle: MotionCycle, at date: Date) -> Double? {
        let playing = Double(cycle.phases.count) * cycle.frameInterval
        let length = playing + cycle.rest
        guard length > 0, !cycle.phases.isEmpty else { return nil }
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: length)
        guard time < playing else { return nil }
        return cycle.phases[min(Int(time / cycle.frameInterval), cycle.phases.count - 1)]
    }
}

extension MotionPreview {
    /// Sample batteries for each state, as the previews show them.
    enum Sample {
        static let charging = BatterySnapshot(percentage: 45, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600)
        static let trickling = BatterySnapshot(
            percentage: 77, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 600, chargeTarget: 80)
        static let holding = BatterySnapshot(
            percentage: 80, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil, chargeTarget: 80)
    }
}
