import AppKit
import BatteryKit
import SwiftUI

/// The panel's sleep, as two detail rows: how much battery the last sleep used, and what's keeping the Mac awake.
struct SleepSection: View {
    let sleep: SleepMonitor
    let usesColor: Bool
    let rowHeight: CGFloat

    /// Something to show: a sleep on record, or something keeping the Mac awake.
    static func applies(to sleep: SleepMonitor) -> Bool {
        sleep.log.last != nil || !sleep.holders.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sleep")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)

            if let last = sleep.log.last {
                row("Last Sleep") {
                    Text(Self.summary(last))
                        .monospacedDigit()
                        .foregroundStyle(drainStyle(last.drain))
                }
                .help(Self.help(last))
            }

            if !sleep.holders.isEmpty {
                AwakeHoldersRow(holders: sleep.holders, rowHeight: rowHeight)
                    .help(sleep.holders.map(\.description).joined(separator: "\n"))
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: sleep.holders.map(\.id))
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 8)
            value()
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .combine)
    }

    private func drainStyle(_ drain: SleepDrain) -> AnyShapeStyle {
        guard usesColor else { return AnyShapeStyle(.primary) }
        switch drain {
        case .heavy: return AnyShapeStyle(.red)
        case .elevated: return AnyShapeStyle(.orange)
        case .normal, .unknown: return AnyShapeStyle(.primary)
        }
    }

    /// "8h 12m · 6 % used", or "8h 12m · plugged in".
    static func summary(_ session: SleepSession) -> String {
        let duration = DurationText.short(session.duration)
        guard let used = session.used else { return String(localized: "\(duration) · plugged in") }
        let percent = (Double(used) / 100).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(duration) · \(percent) used")
    }

    static func help(_ session: SleepSession) -> String {
        let ended = session.end.formatted(.relative(presentation: .named))
        let rate = session.perHour.map { String(localized: "About \($0.formatted(.number.precision(.fractionLength(1))))% an hour.") }
        let verdict: String =
            switch session.drain {
            case .heavy:
                String(
                    localized:
                        "Much more than a sleep should use. Usually something kept waking the Mac: a Bluetooth device, Wake for network access in System Settings › Battery, or an app."
                )
            case .elevated: String(localized: "A little more than usual. A Mac asleep should use about 1% an hour.")
            case .normal: String(localized: "A normal sleep.")
            case .unknown: String(localized: "Plugged in, or too short to say how fast it used the battery.")
            }
        return [String(localized: "Woke \(ended)."), rate, verdict].compactMap(\.self).joined(separator: " ")
    }
}

/// "Kept Awake By  [icon] Slack 🔊", in one line like the panel's other rows: the app's icon and name, and a small
/// symbol for what it's doing (playing sound, using the microphone, keeping the display on). For several, their icons
/// overlap and the name reads "Slack +2". The tooltip says the rest.
private struct AwakeHoldersRow: View {
    let holders: [AwakeHolder]
    let rowHeight: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Kept Awake By")
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 8)
            icons
            Text(names)
                .truncationMode(.middle)
                .layoutPriority(-1)
            if let activity {
                Image(systemName: activity.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(spokenActivity(activity))
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .combine)
    }

    /// Up to three icons, overlapping a little, like a stack of cards.
    private var icons: some View {
        HStack(spacing: -5) {
            ForEach(holders.prefix(3)) { holder in
                HolderIcon(holder: holder, size: 16)
                    .shadow(color: .black.opacity(holders.count > 1 ? 0.18 : 0), radius: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var names: String {
        guard let first = holders.first else { return "" }
        return holders.count == 1 ? first.name : "\(first.name) +\(holders.count - 1)"
    }

    /// The most telling thing any of them is doing; nothing when that's only "keeping the Mac awake".
    private var activity: AwakeHolder.Activity? {
        let most = holders.map(\.activity).max() ?? .other
        return most == .other ? nil : most
    }

    private func spokenActivity(_ activity: AwakeHolder.Activity) -> String {
        switch activity {
        case .microphone: String(localized: "Using the microphone")
        case .audio: String(localized: "Playing audio")
        case .display: String(localized: "Keeps the display on")
        case .other: String(localized: "Keeps the Mac awake")
        }
    }
}

/// An app's icon, or a symbol for a command-line tool or a part of macOS.
struct HolderIcon: View {
    let holder: AwakeHolder
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = holder.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: holder.id == "process:coreaudiod" ? "speaker.wave.2.fill" : "terminal.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.82, height: size * 0.82)
                    .background(.gray.gradient, in: .rect(cornerRadius: size * 0.2, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

/// An app or tool keeping the Mac awake, for Settings › Sleep: its icon, its name and why.
struct AwakeHolderRow: View {
    let holder: AwakeHolder

    var body: some View {
        LabeledContent {
            Text(holder.effect == .keepsDisplayOn ? "Keeps the display on" : "Keeps the Mac awake")
                .foregroundStyle(.secondary)
        } label: {
            HStack(spacing: 8) {
                HolderIcon(holder: holder, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(holder.name)
                    if let reason = holder.reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

extension AwakeHolder: CustomStringConvertible {
    /// "zoom.us: Zoom meeting in progress"
    var description: String {
        reason.map { "\(name): \($0)" } ?? name
    }
}
