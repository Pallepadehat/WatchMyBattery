import BatteryKit
import SwiftUI

/// "Charge Limit  80 %": macOS's charge limit, in the panel's rhythm of a label and its value. Clicking the value
/// offers the other levels, and a one-off charge to full.
struct ChargeLimitRow: View {
    let chargeLimit: ChargeLimit

    var body: some View {
        HStack(spacing: 6) {
            Text("Charge Limit")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if chargeLimit.isChanging {
                ProgressView()
                    .controlSize(.mini)
            }
            Menu {
                ForEach(chargeLimit.choices.reversed(), id: \.self) { level in
                    Toggle(isOn: Binding(get: { level == chargeLimit.limit && !chargeLimit.isToppingUp }, set: { _ in chargeLimit.set(level) })) {
                        Text(level == ChargeLimitClient.Levels.noLimit ? String(localized: "None") : Self.percent(level))
                    }
                }
                Divider()
                if chargeLimit.isToppingUp {
                    Button("Put the Limit Back Now") { chargeLimit.cancelTopUp() }
                } else {
                    Button("Charge to Full Once") { chargeLimit.chargeToFullOnce() }
                        .disabled(!chargeLimit.isLimited)
                }
            } label: {
                HStack(spacing: 3) {
                    Text(value)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(chargeLimit.isChanging)
        }
        .font(.system(size: 12))
        .help(
            "Holds the battery at this level while plugged in, so it lasts longer. macOS keeps it, even when WatchMyBattery isn't running."
        )
    }

    private var value: String {
        if chargeLimit.isToppingUp { return String(localized: "\(Self.percent(100)) Once") }
        return chargeLimit.isLimited ? Self.percent(chargeLimit.limit) : String(localized: "None")
    }

    static func percent(_ level: Int) -> String {
        (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
