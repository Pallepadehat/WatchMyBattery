import BatteryKit
import SwiftUI

/// The big battery in the panel.
///
/// The pill is the battery time you have: the white part is the time left
/// with everything running, and each coloured slice after it is the time an
/// app is costing you, with that cost written underneath. Quit an app and its
/// slice turns back into white time. Drag a slice out of the panel to quit
/// that app.
struct BatteryGauge: View {
    let snapshot: BatterySnapshot
    let apps: [AppUsage]
    let estimates: Estimates
    let centerLabel: CenterLabel
    let usesColor: Bool
    @Binding var focusedApp: AppUsage?
    let quit: (AppUsage) -> Void

    @State private var draggedApp: AppUsage.ID?

    private static let height: CGFloat = 72
    private static let terminalSize = CGSize(width: 6, height: 28)
    private static let terminalGap: CGFloat = 5
    private static let labelHeight: CGFloat = 14
    /// Room "4:50" needs in the white part.
    private static let labelWidth: CGFloat = 84

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Self.terminalGap) {
                GeometryReader { geometry in
                    let layout = layout(width: geometry.size.width)
                    pill(layout)
                        .overlay(alignment: .topLeading) {
                            costLabels(layout)
                                .offset(y: Self.height + 6)
                        }
                }
                .frame(height: Self.height)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.secondary.opacity(0.6))
                    .frame(width: Self.terminalSize.width, height: Self.terminalSize.height)
            }
            Color.clear.frame(height: Self.labelHeight)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Layout

    /// Each app's share of the pill: its cost out of all the time there'd be
    /// without it. On the adapter, where time doesn't apply, its share of the power draw.
    private func layout(width: CGFloat) -> GaugeLayout {
        let shares: [Double]
        if estimates.appliesToTime, let timeRemaining = snapshot.timeRemaining {
            let costs = apps.map { estimates.timeGained(byQuitting: $0.watts) }
            let total = timeRemaining + costs.reduce(0, +)
            shares = costs.map { total > 0 ? $0 / total : 0 }
        } else {
            shares = apps.map { estimates.share(of: $0.watts) }
        }
        return GaugeLayout(width: width, level: 1, shares: shares, minimumSliceWidth: 36, labelWidth: Self.labelWidth)
    }

    // MARK: - The pill

    private func pill(_ layout: GaugeLayout) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(baseFill)
                centerText
            }
            .frame(width: layout.baseWidth)

            ForEach(Array(zip(apps.prefix(layout.sliceWidths.count), layout.sliceWidths)), id: \.0.id) { app, width in
                AppSlice(
                    app: app,
                    isDragged: draggedApp == app.id,
                    focusedApp: $focusedApp,
                    draggedApp: $draggedApp,
                    quit: quit
                )
                .frame(width: width)
                .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)))
            }
        }
        .clipShape(.capsule(style: .continuous))
    }

    /// White, or green while charging and red when low if colours are on.
    private var baseFill: Color {
        guard usesColor else { return .white }
        switch snapshot.chargeState {
        case .charging: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .discharging where snapshot.percentage <= BatteryIcon.lowPercentage: return Color(red: 0.95, green: 0.27, blue: 0.23)
        default: return .white
        }
    }

    private var isTinted: Bool { baseFill != .white }

    private var centerText: some View {
        HStack(spacing: 4) {
            if snapshot.isCharging {
                Image(systemName: "bolt.fill").font(.system(size: 18, weight: .bold))
            } else if snapshot.chargeState == .notCharging {
                Image(systemName: "powerplug.fill").font(.system(size: 17, weight: .semibold))
            }
            Text(centerString)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(isTinted ? Color.white : Color.black.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 8)
    }

    private var centerString: String {
        let percentage = snapshot.level.formatted(.percent.precision(.fractionLength(0)))
        guard centerLabel == .timeRemaining else { return percentage }
        switch snapshot.chargeState {
        case .discharging, .charging:
            return snapshot.timeRemaining.map(TimeFormat.clock) ?? percentage
        case .charged, .notCharging:
            return percentage
        }
    }

    // MARK: - Costs under the slices

    private func costLabels(_ layout: GaugeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(apps.prefix(layout.sliceWidths.count), zip(layout.sliceOffsets, layout.sliceWidths))), id: \.0.id) {
                app, frame in
                Text(costText(for: app))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(focusedApp?.id == app.id ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: frame.1)
                    .offset(x: frame.0)
                    .opacity(draggedApp == app.id ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func costText(for app: AppUsage) -> String {
        if estimates.appliesToTime {
            let cost = estimates.timeGained(byQuitting: app.watts)
            return cost >= 60 ? TimeFormat.cost(cost) : "<1m"
        }
        return app.watts.formatted(.number.precision(.fractionLength(1))) + " W"
    }
}

/// One app's slice: its colour, its icon, and the drag that quits it.
private struct AppSlice: View {
    let app: AppUsage
    let isDragged: Bool
    @Binding var focusedApp: AppUsage?
    @Binding var draggedApp: AppUsage.ID?
    let quit: (AppUsage) -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(app.tint)
                .overlay(.white.opacity(isHovered && !isDragged ? 0.16 : 0))
                .opacity(isDragged ? 0.25 : 1)

            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                .scaleEffect(isHovered ? 1.12 : 1)
                .opacity(isDragged ? 0 : 1)
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.15)).frame(width: 1)
        }
        .contentShape(.rect)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.18)) { isHovered = hovering }
            if hovering {
                focusedApp = app
                NSCursor.openHand.set()
            } else {
                if focusedApp?.id == app.id && draggedApp != app.id { focusedApp = nil }
                if draggedApp == nil { NSCursor.arrow.set() }
            }
        }
        .gesture(dragToQuit)
        .contextMenu {
            Button("Quit \(app.name)") { quit(app) }
            Button("Show \(app.name)") {
                NSRunningApplication(processIdentifier: app.id)?.activate()
            }
        }
        .help(app.name)
        .accessibilityElement()
        .accessibilityLabel(app.name)
        .accessibilityHint("Drag out of the panel to quit")
        .accessibilityAction(named: "Quit \(app.name)") { quit(app) }
    }

    private var dragToQuit: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                let pointer = NSEvent.mouseLocation
                let controller = DragToQuitController.shared
                if draggedApp != app.id {
                    let panelFrame = NSApp.windows.first { $0 is BatteryPanel }?.frame ?? .zero
                    controller.begin(app, at: pointer, panelFrame: panelFrame)
                    NSCursor.closedHand.set()
                    withAnimation(.snappy(duration: 0.2)) { draggedApp = app.id }
                    focusedApp = app
                }
                controller.move(to: pointer)
            }
            .onEnded { _ in
                let quits = DragToQuitController.shared.end(at: NSEvent.mouseLocation)
                NSCursor.arrow.set()
                if quits {
                    quit(app)
                }
                withAnimation(.snappy(duration: 0.25).delay(quits ? 0 : 0.18)) { draggedApp = nil }
                focusedApp = nil
            }
    }
}
