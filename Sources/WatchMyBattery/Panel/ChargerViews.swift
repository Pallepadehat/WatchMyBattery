import BatteryKit
import SwiftUI

/// "Charger  12 W of 96 W": what the Mac is getting from the connected charger, out of what it can give, as one of the
/// panel's detail rows, with a warning when something's wrong with it.
struct ChargerRow: View {
    let adapter: PowerAdapter
    /// What's coming in right now, while the panel measures it.
    var chargerWatts: Double? = nil
    let note: ChargingNote?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Charger")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if isStruggling {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .transition(.scale.combined(with: .opacity))
            }
            if let incoming {
                Text(incoming)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .help(help)
        .accessibilityElement(children: .combine)
    }

    /// The watts, which tell one charger from another; the name when macOS doesn't give them.
    private var value: String {
        if let watts = adapter.watts { return "\(watts) W" }
        return adapter.name ?? ""
    }

    /// "12 W of": what's in use of what the charger can give. Only beside the charger's own watts, which it qualifies.
    private var incoming: String? {
        guard let chargerWatts, adapter.watts != nil else { return nil }
        return String(localized: "\(PowerFormat.watts(chargerWatts)) of", comment: "Before a charger's watts: \"12 W of\" 96 W")
    }

    private var help: String {
        let name = adapter.name ?? String(localized: "The charger the Mac is plugged into.")
        guard let chargerWatts else { return name }
        return name + "\n" + String(localized: "Your Mac is getting \(PowerFormat.watts(chargerWatts)) from it right now, for itself and its battery.")
    }

    private var isStruggling: Bool {
        switch note {
        case .adapterTooWeak, .chargingSlowly, .notGettingFullPower: true
        default: false
        }
    }
}

/// Why charging is paused or slow, in a few words, under the panel's details. It isn't dismissed: it goes away by
/// itself once the reason does.
struct ChargingNoteCard: View {
    let note: ChargingNote

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch note {
        case .pausedWhileHot, .slowedByHeat: "thermometer.high"
        case .adapterTooWeak, .notGettingFullPower: "powerplug.fill"
        case .chargingSlowly: "tortoise.fill"
        case .restingNearTarget: "leaf.fill"
        }
    }

    private var tint: Color {
        switch note {
        case .pausedWhileHot: .red
        case .slowedByHeat, .adapterTooWeak, .notGettingFullPower: .orange
        case .chargingSlowly: .yellow
        case .restingNearTarget: ChargeTrack.green
        }
    }

    private var title: String {
        switch note {
        case .pausedWhileHot: String(localized: "Charging paused while the battery cools")
        case .slowedByHeat: String(localized: "Charging slowly while the battery is warm")
        case .adapterTooWeak: String(localized: "The charger can't keep up")
        case .notGettingFullPower: String(localized: "Running on battery while plugged in")
        case .chargingSlowly: String(localized: "Charging slowly")
        case .restingNearTarget(let target) where target >= 100: String(localized: "Nearly full")
        case .restingNearTarget(let target): String(localized: "Holding near \(Self.percent(target))")
        }
    }

    private var detail: String {
        switch note {
        case .pausedWhileHot(let temperature):
            String(
                localized:
                    "It's \(BatteryReadingsRows.format(temperature: temperature)). macOS holds charging back while the battery is this warm, and carries on by itself once it cools."
            )
        case .slowedByHeat(let temperature):
            String(localized: "It's \(BatteryReadingsRows.format(temperature: temperature)), so macOS charges more gently until it cools down.")
        case .adapterTooWeak(let adapterWatts, let systemWatts):
            String(
                localized:
                    "Your Mac is using about \(PowerFormat.watts(systemWatts)), about all the \(adapterWatts) W charger can give, so there's none left for the battery. A more powerful charger, or quitting busy apps, helps."
            )
        case .notGettingFullPower(let adapterWatts?, let chargerWatts?) where chargerWatts < 1:
            String(
                localized:
                    "Your Mac isn't taking power from the \(adapterWatts) W charger right now. If another battery app is set to discharge it, that's why; otherwise, try plugging the charger in again."
            )
        case .notGettingFullPower(_, let chargerWatts?) where chargerWatts < 1:
            String(
                localized:
                    "Your Mac isn't taking power from the charger right now. If another battery app is set to discharge it, that's why; otherwise, try plugging the charger in again."
            )
        case .notGettingFullPower(let adapterWatts?, let chargerWatts?):
            String(
                localized:
                    "Your Mac is only getting \(PowerFormat.watts(chargerWatts)) from the \(adapterWatts) W charger, so the battery makes up the rest. Another cable or port, or plugging the charger straight into the Mac, usually helps."
            )
        case .notGettingFullPower:
            String(
                localized:
                    "The battery is running down, though your Mac isn't using more than the charger should give. Another cable or port, or plugging the charger straight into the Mac, usually helps."
            )
        case .chargingSlowly(let adapterWatts, let systemWatts):
            String(
                localized:
                    "Your Mac is using about \(PowerFormat.watts(systemWatts)) of the \(adapterWatts) W charger's power, leaving little for the battery."
            )
        case .restingNearTarget(let target) where target >= 100:
            String(localized: "macOS lets the battery drift down a little before topping it up, so it isn't kept at \(Self.percent(100)) all the time.")
        case .restingNearTarget:
            String(localized: "macOS charges again once the battery has drifted down a little further.")
        }
    }

    private static func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
