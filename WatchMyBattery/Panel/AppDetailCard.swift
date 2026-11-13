import AppKit
import BatteryKit
import SwiftUI

/// What opens under the battery when a slice is clicked: the processes behind its slice (which browser helper,
/// which renderer), and ways to make it stop: Quit, or Force Quit for an app that's stopped responding. Styled
/// like the panel's other notices.
struct AppDetailCard: View {
    let app: AppUsage
    let processes: [ProcessEnergy]
    let quit: () -> Void
    let forceQuit: () -> Void
    let close: () -> Void

    /// Force Quit was pressed once: it asks again, as unsaved work will be lost.
    @State private var isConfirmingForceQuit = false

    private static let maximumRows = 5

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                processList
                actions
            }
            Spacer(minLength: 0)
            DismissButton(action: close)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
        .onChange(of: app.id) { isConfirmingForceQuit = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
    }

    @ViewBuilder private var processList: some View {
        if processes.isEmpty {
            Text("Measuring its processes…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(processes.prefix(Self.maximumRows)) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(process.name)
                        Spacer(minLength: 6)
                        Text(Self.watts(process.watts))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                }
                if processes.count > Self.maximumRows {
                    let rest = processes.dropFirst(Self.maximumRows)
                    HStack {
                        Text("\(rest.count) more")
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 6)
                        Text(Self.watts(rest.reduce(0) { $0 + $1.watts }))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.system(size: 11))
            .animation(.snappy(duration: 0.3), value: processes.prefix(Self.maximumRows).map(\.pid))
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Show") { NSRunningApplication(processIdentifier: app.id)?.activate() }
            Button("Quit", action: quit)
            if isConfirmingForceQuit {
                Button("Force Quit, Losing Unsaved Changes", action: forceQuit)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            } else {
                Button("Force Quit…") { withAnimation(.snappy(duration: 0.2)) { isConfirmingForceQuit = true } }
                    .help("For an app that's stopped responding: quits it straight away, without asking about unsaved changes.")
            }
        }
        .buttonStyle(.link)
        .font(.system(size: 11, weight: .medium))
    }

    static func watts(_ watts: Double) -> String {
        guard watts >= 0.05 else { return "<" + (0.1).formatted(.number.precision(.fractionLength(1))) + " W" }
        return watts.formatted(.number.precision(.fractionLength(1))) + " W"
    }
}
