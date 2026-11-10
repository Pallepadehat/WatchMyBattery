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
    @Environment(\.colorScheme) private var colorScheme

    /// Solid white on dark, black on light, like the menu bar icon. Explicit
    /// colours, because glass would tint `.primary` into a washed-out grey.
    private var ink: Color { colorScheme == .dark ? .white : .black }

    // MARK: Geometry: the menu bar icon, scaled up

    /// The menu bar icon's proportions (about 2:1), just bigger.
    private static let size = CGSize(width: 196, height: 84)
    private static var height: CGFloat { size.height }
    private static var cornerRadius: CGFloat { size.height * 0.3 }
    private static let terminalSize = CGSize(width: 6, height: 26)
    /// Room "4:50" needs.
    private static let labelWidth: CGFloat = 80
    private static let terminalGap: CGFloat = 3
    /// The thin gap between the charge and each app, cut through the pill.
    static let seam: CGFloat = 2
    /// How strongly the drained part shows, the same as in the menu bar.
    private static let emptyOpacity = 0.2

    var body: some View {
        HStack(spacing: Self.terminalGap) {
            GeometryReader { geometry in
                let layout = layout(width: geometry.size.width)
                ZStack(alignment: .leading) {
                    // The drained part, after the charge.
                    Rectangle()
                        .fill(ink.opacity(Self.emptyOpacity))
                        .padding(.leading, layout.fillWidth + Self.seam)

                    cells(layout)

                    if !labelFitsInFill(layout) {
                        centerText
                            .frame(width: max(geometry.size.width - layout.fillWidth - Self.seam, 0))
                            .offset(x: layout.fillWidth + Self.seam)
                    }
                }
                .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
            }
            .frame(width: Self.size.width, height: Self.size.height)

            terminal
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// The small half-round nub.
    private var terminal: some View {
        UnevenRoundedRectangle(bottomTrailingRadius: Self.terminalSize.width, topTrailingRadius: Self.terminalSize.width)
            .fill(ink.opacity(snapshot.level >= 0.995 ? 1 : Self.emptyOpacity * 1.6))
            .frame(width: Self.terminalSize.width, height: Self.terminalSize.height)
    }

    // MARK: - Layout

    private func layout(width: CGFloat) -> GaugeLayout {
        GaugeLayout(
            width: width, level: snapshot.level, shares: apps.map { estimates.share(of: $0.watts) }, labelWidth: Self.labelWidth)
    }

    // MARK: - Charge and apps

    /// The charge, then one cell per app, separated by thin seams.
    private func cells(_ layout: GaugeLayout) -> some View {
        HStack(spacing: Self.seam) {
            Rectangle()
                .fill(chargeFill)
                .overlay {
                    if labelFitsInFill(layout) {
                        centerText
                            .padding(.horizontal, 6)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
                .frame(width: max(layout.baseWidth - Self.seam, 0))

            ForEach(Array(zip(apps.prefix(layout.sliceWidths.count), layout.sliceWidths)), id: \.0.id) { app, width in
                AppSlice(
                    app: app,
                    cost: costText(for: app),
                    isDragged: draggedApp == app.id,
                    focusedApp: $focusedApp,
                    draggedApp: $draggedApp,
                    quit: quit
                )
                .frame(width: max(width - Self.seam, 0))
                .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)))
            }
        }
        .frame(width: layout.fillWidth, alignment: .leading)
    }

    /// The charge: solid like the menu bar icon, green while charging and red when low.
    private var chargeFill: AnyShapeStyle {
        switch (usesColor, snapshot.chargeState) {
        case (true, .charging):
            AnyShapeStyle(Color.green)
        case (true, .discharging) where snapshot.percentage <= BatteryIcon.lowPercentage:
            AnyShapeStyle(Color.red)
        default:
            AnyShapeStyle(ink)
        }
    }

    /// Room for "4:50" in the plain part of the fill; otherwise it moves to the empty part.
    private func labelFitsInFill(_ layout: GaugeLayout) -> Bool {
        layout.baseWidth >= Self.labelWidth
    }

    /// The time (or percentage). On the charge it's cut out of the pill, like
    /// the number in the menu bar icon; on the drained part it's drawn plainly.
    private var centerText: some View {
        HStack(spacing: 3) {
            if snapshot.isCharging {
                Image(systemName: "bolt.fill").font(.system(size: 17, weight: .bold))
            } else if snapshot.chargeState == .notCharging {
                Image(systemName: "powerplug.fill").font(.system(size: 16, weight: .semibold))
            }
            Text(centerString)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(ink)
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

    // MARK: - Costs

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
    /// What the app costs: "−48m" on battery, its watts on the adapter.
    let cost: String
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

            VStack(spacing: 3) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                    .scaleEffect(isHovered ? 1.12 : 1)
                Text(cost)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
                    .contentTransition(.numericText())
            }
            .opacity(isDragged ? 0 : 1)
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
