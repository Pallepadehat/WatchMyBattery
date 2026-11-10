import BatteryKit
import SwiftUI

/// The big battery in the panel.
///
/// The fill is the charge that's left. Coloured slices at its end are the
/// apps that will use that charge, sized by their share of the Mac's power
/// draw, with the time each one costs underneath. Drag a slice out of the
/// panel to quit that app.
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
    private static let terminalWidth: CGFloat = 5
    private static let terminalGap: CGFloat = 3
    private static let labelHeight: CGFloat = 16

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: Self.terminalGap) {
                GeometryReader { geometry in
                    let layout = layout(width: geometry.size.width)
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(.primary.opacity(0.08))

                        fill(layout)

                        if !labelFitsInFill(layout) {
                            centerText(onFill: false)
                                .frame(width: max(geometry.size.width - layout.fillWidth, 0))
                                .offset(x: layout.fillWidth)
                        }

                        Capsule(style: .continuous)
                            .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                    }
                    .clipShape(.capsule(style: .continuous))
                    .overlay(alignment: .topLeading) {
                        costLabels(layout)
                            .offset(y: Self.height + 5)
                    }
                }
                .frame(height: Self.height)

                UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    .fill(.primary.opacity(snapshot.level >= 0.995 ? 0.5 : 0.2))
                    .frame(width: Self.terminalWidth, height: Self.height * 0.36)
            }
            Color.clear.frame(height: Self.labelHeight)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Layout

    private func layout(width: CGFloat) -> GaugeLayout {
        GaugeLayout(width: width, level: snapshot.level, shares: apps.map { estimates.share(of: $0.watts) })
    }

    // MARK: - Fill

    private func fill(_ layout: GaugeLayout) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(baseFill)
                if labelFitsInFill(layout) {
                    centerText(onFill: true)
                        .padding(.horizontal, 6)
                }
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
        .frame(width: layout.fillWidth, alignment: .leading)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 3, x: 1)
    }

    private var baseFill: AnyShapeStyle {
        guard usesColor else { return AnyShapeStyle(Color.white) }
        switch snapshot.chargeState {
        case .charging:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.3, green: 0.85, blue: 0.45), .green], startPoint: .leading, endPoint: .trailing))
        case .discharging where snapshot.percentage <= BatteryIcon.lowPercentage:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.38), .red], startPoint: .leading, endPoint: .trailing))
        default:
            return AnyShapeStyle(Color.white)
        }
    }

    private var isTintedFill: Bool {
        usesColor && (snapshot.isCharging || (snapshot.chargeState == .discharging && snapshot.percentage <= BatteryIcon.lowPercentage))
    }

    /// Room for "4:50" in the plain part of the fill; otherwise it moves to the empty part.
    private func labelFitsInFill(_ layout: GaugeLayout) -> Bool {
        layout.baseWidth >= 66
    }

    private func centerText(onFill: Bool) -> some View {
        HStack(spacing: 3) {
            if snapshot.isCharging {
                Image(systemName: "bolt.fill").font(.system(size: 15, weight: .bold))
            } else if snapshot.chargeState == .notCharging {
                Image(systemName: "powerplug.fill").font(.system(size: 14, weight: .semibold))
            }
            Text(centerString)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(onFill ? AnyShapeStyle(isTintedFill ? Color.white : Color.black.opacity(0.85)) : AnyShapeStyle(.primary))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
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

    // MARK: - Labels under the slices

    private func costLabels(_ layout: GaugeLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(apps.prefix(layout.sliceWidths.count), zip(layout.sliceOffsets, layout.sliceWidths))), id: \.0.id) {
                app, frame in
                Text(costText(for: app))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(focusedApp?.id == app.id ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: frame.1 + 2)
                    .offset(x: frame.0 - 1)
                    .opacity(draggedApp == app.id ? 0 : 1)
            }
        }
        .contentTransition(.numericText())
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
                .fill(app.tint.gradient)
                .overlay(.white.opacity(isHovered && !isDragged ? 0.14 : 0))
                .opacity(isDragged ? 0.35 : 1)

            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .scaleEffect(isHovered ? 1.15 : 1)
                .opacity(isDragged ? 0 : 1)
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.18)).frame(width: 1)
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
