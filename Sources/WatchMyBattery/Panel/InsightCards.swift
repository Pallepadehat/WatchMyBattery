import AppKit
import BatteryKit
import SwiftUI

/// The insights that apply right now, one card each: a meeting the battery
/// won't last through, more power than usual, a new app using a lot.
struct InsightCards: View {
    let insights: InsightsMonitor
    let snapshot: BatterySnapshot
    /// Low Power Mode can be turned on from here; `nil` where it isn't supported.
    let turnOnLowPowerMode: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if let meeting = insights.meeting {
                InsightCard(
                    title: InsightText.meetingTitle(meeting), detail: InsightText.meetingDetail(meeting),
                    action: snapshot.isLowPowerModeOn ? nil : turnOnLowPowerMode.map { (String(localized: "Turn On Low Power Mode"), $0) },
                    dismiss: { withAnimation(.snappy) { insights.dismissMeeting() } }
                ) {
                    symbol("calendar.badge.clock", .orange)
                }
                .transition(Self.transition)
            }

            if let drain = insights.unusualDrain, !insights.isUnusualDrainDismissed {
                InsightCard(
                    title: InsightText.unusualDrainTitle, detail: InsightText.unusualDrainDetail(drain),
                    action: drain.cause.flatMap(quitAction),
                    dismiss: { withAnimation(.snappy) { insights.dismissUnusualDrain() } }
                ) {
                    symbol("chart.line.uptrend.xyaxis", .purple)
                }
                .transition(Self.transition)
            }

            ForEach(insights.newApps) { app in
                InsightCard(
                    title: InsightText.newAppTitle(app.app), detail: InsightText.newAppDetail,
                    action: quitAction(app.app),
                    dismiss: { withAnimation(.snappy) { insights.dismissNewApp(app.id) } }
                ) {
                    Image(nsImage: AppLook.of(app.app).icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                }
                .transition(Self.transition)
            }
        }
        .animation(.snappy(duration: 0.3), value: insights.meeting)
        .animation(.snappy(duration: 0.3), value: insights.unusualDrain)
        .animation(.snappy(duration: 0.3), value: insights.newApps.map(\.id))
    }

    static func hasAny(_ insights: InsightsMonitor) -> Bool {
        insights.meeting != nil || (insights.unusualDrain != nil && !insights.isUnusualDrainDismissed) || !insights.newApps.isEmpty
    }

    private static let transition = AnyTransition.opacity.combined(with: .move(edge: .top))

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15))
            .foregroundStyle(color)
            .frame(width: 22)
            .padding(.top, 1)
    }

    /// "Quit Xcode", while it's running.
    private func quitAction(_ app: BatteryHistory.AppIdentity) -> (String, () -> Void)? {
        guard let bundleIdentifier = app.bundleIdentifier,
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated })
        else { return nil }
        return (String(localized: "Quit \(app.name)"), { running.terminate() })
    }
}

/// One insight: an icon, what it is, why, maybe something to do about it, and a way to dismiss it.
private struct InsightCard<Icon: View>: View {
    let title: String
    let detail: String
    let action: (String, () -> Void)?
    let dismiss: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let (label, perform) = action {
                    Button(label, action: perform)
                        .buttonStyle(.link)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            Spacer(minLength: 0)
            DismissButton(title: title, action: dismiss)
        }
        .padding(10)
        // One quiet fill for every card, the colour kept to the icon, so a few insights together don't crowd the panel.
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
