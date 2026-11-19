import BatteryKit
import SwiftUI

/// What opens under the battery when Display & System is clicked: macOS's processes that have no slice of their own,
/// and what's left once they're counted, which is the screen and the rest of the hardware. macOS reports the whole
/// Mac's power, and each process's, but not the screen's or Wi‑Fi's on their own, so that part is one line, honestly
/// named, with what makes it smaller.
struct SystemDetailCard: View {
    let breakdown: SystemBreakdown?
    let openDisplaySettings: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: SystemIcons.displays)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Display & System")
                        .font(.system(size: 12, weight: .semibold))
                    Text("The screen, Wi‑Fi and the parts of macOS with no slice of their own.")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let breakdown {
                    rows(breakdown)
                } else {
                    Text("Measuring…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button("Displays Settings…", action: openDisplaySettings)
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
            }
            Spacer(minLength: 0)
            DismissButton(action: close)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display and system")
    }

    private func rows(_ breakdown: SystemBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            row(
                Text("Screen & hardware"), icon: SystemIcons.displays, watts: breakdown.hardwareWatts, estimated: false, emphasised: true,
                help:
                    "The screen's backlight, Wi‑Fi, memory, storage and the rest of the hardware: macOS reports them together, not one by one. A dimmer screen makes this smaller."
            )
            if !breakdown.processes.isEmpty {
                Text("macOS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                ForEach(breakdown.processes) { process in
                    row(
                        Text(verbatim: process.name), icon: SystemIcons.icon(forProcessNamed: process.name), watts: process.watts,
                        estimated: process.isEstimated, emphasised: false, help: nil)
                }
            }
        }
        .font(.system(size: 11))
        .animation(.snappy(duration: 0.3), value: breakdown.processes.map(\.pid))
    }

    private func row(_ title: Text, icon: NSImage, watts: Double, estimated: Bool, emphasised: Bool, help: LocalizedStringKey?) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
            title
                .fontWeight(emphasised ? .medium : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(AppDetailCard.watts(watts, estimated: estimated))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .help(help.map { Text($0) } ?? Text(estimated ? "Worked out from its CPU time: macOS doesn't show its energy." : ""))
        .accessibilityElement(children: .combine)
    }
}
