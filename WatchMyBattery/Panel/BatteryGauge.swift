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
    /// Play the charging animation (the setting is on, the panel is open, and it's charging).
    let animatesCharging: Bool
    @Binding var focusedApp: AppUsage?
    /// Quits right away (asking first only if the user wants that): a drag out of the panel.
    let quit: (AppUsage) -> Void
    /// Always asks first: ⌫ on a slice, where a stray key press shouldn't cost unsaved work.
    let confirmQuit: (AppUsage) -> Void
    /// Never give this app a slice again.
    let exclude: ((AppUsage) -> Void)?
    /// The power no app accounts for (display, graphics, radios, macOS), for a slice of its own; `nil` for none.
    var systemWatts: Double? = nil
    /// Never give Display & System a slice again (it can be turned back on in Settings › Panel).
    var hideSystem: (() -> Void)? = nil
    /// The app whose processes are listed under the battery.
    var inspectedApp: pid_t? = nil
    /// Click on a slice: list its processes (or stop listing them).
    var inspect: (AppUsage) -> Void = { _ in }

    @State private var draggedApp: AppUsage.ID?
    /// The slice with focus (Tab moves between slices).
    @FocusState private var focusedSlice: AppUsage.ID?
    /// The focused slice, but only once the keyboard put it there. SwiftUI
    /// focuses the first slice by itself when the panel opens, which shouldn't
    /// draw a ring, preview anything, or let ⌫ quit that app.
    @State private var keyboardSlice: AppUsage.ID?
    @Environment(\.colorScheme) private var colorScheme

    private static let height: CGFloat = 72
    /// Rounded like the menu bar icon, leaving a flat end for the terminal.
    private static let cornerRadius: CGFloat = 22
    private static let terminalSize = CGSize(width: 6, height: 26)
    private static let terminalGap: CGFloat = 2
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

                // The terminal: a half-round nub right against the body, as in the menu bar icon.
                UnevenRoundedRectangle(
                    bottomTrailingRadius: Self.terminalSize.width, topTrailingRadius: Self.terminalSize.width,
                    style: .continuous
                )
                .fill(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.28))
                .frame(width: Self.terminalSize.width, height: Self.terminalSize.height)
            }
            Color.clear.frame(height: Self.labelHeight)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: focusedSlice) { old, new in
            let fromKeyboard = NSApp.currentEvent?.type == .keyDown
            keyboardSlice = fromKeyboard ? new : nil
            // Keyboard focus previews the time quitting would give back, like hovering does.
            if fromKeyboard, let new, let app = apps.first(where: { $0.id == new }) {
                focusedApp = app
            } else if let old, focusedApp?.id == old, draggedApp == nil {
                focusedApp = nil
            }
        }
    }

    // MARK: - Layout

    /// A slice of the pill: an app's, or the one for display and system.
    private struct Piece: Identifiable {
        enum Kind {
            case app(AppUsage)
            case system(watts: Double)
        }

        let kind: Kind
        let offset: CGFloat
        let width: CGFloat

        var id: String {
            switch kind {
            case .app(let app): "app-\(app.id)"
            case .system: "system"
            }
        }
    }

    private struct Layout {
        let baseWidth: CGFloat
        let pieces: [Piece]
    }

    /// Each app's share of the pill: its cost out of all the time there'd be
    /// without it. On the adapter, where time doesn't apply, its share of the power draw.
    ///
    /// Display and system come last, at the end of the battery: what's left once every app has had its share. The
    /// apps come first for room too, as they're what you can do something about; display and system get what's
    /// left, if that's enough for a slice.
    private func layout(width: CGFloat) -> Layout {
        let system = systemWatts.flatMap { $0 >= Self.minimumSystemWatts ? $0 : nil }
        let watts = apps.map(\.watts) + (system.map { [$0] } ?? [])
        let shares = estimates.sliceShares(forAppsDrawing: watts)
        let layout = GaugeLayout(
            width: width, level: 1, shares: shares, minimumSliceWidth: Self.minimumSliceWidth, labelWidth: Self.labelWidth)
        let appWidths = Array(layout.sliceWidths.prefix(apps.count))
        var systemWidth: CGFloat?
        if system != nil {
            if layout.sliceWidths.count > apps.count {
                systemWidth = layout.sliceWidths.last
            } else if appWidths.count == apps.count {
                // Didn't fit at its full share: take the room that's left, if there's enough for a slice.
                let room = width - Self.labelWidth - appWidths.reduce(0, +)
                if room >= Self.minimumSliceWidth { systemWidth = room }
            }
        }
        let used = appWidths.reduce(0, +) + (systemWidth ?? 0)
        let baseWidth = max(width - used, 0)
        var pieces: [Piece] = []
        var offset = baseWidth
        for (app, width) in zip(apps, appWidths) {
            pieces.append(Piece(kind: .app(app), offset: offset, width: width))
            offset += width
        }
        if let system, let systemWidth {
            pieces.append(Piece(kind: .system(watts: system), offset: offset, width: systemWidth))
        }
        return Layout(baseWidth: baseWidth, pieces: pieces)
    }

    private static let minimumSliceWidth: CGFloat = 36

    /// Less than this and it isn't worth a slice: the display is off, or the reading hasn't settled.
    private static let minimumSystemWatts = 0.3

    // MARK: - The pill

    private func pill(_ layout: Layout) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(baseFill)
                if showsChargingAnimation {
                    ChargingWave(color: waveColor, brightens: baseFill != .white)
                        .transition(.opacity)
                }
                centerText
            }
            .chargingAnimation(showsChargingAnimation)
            .frame(width: layout.baseWidth)

            let visible: [AppUsage] = layout.pieces.compactMap {
                if case .app(let app) = $0.kind { app } else { nil }
            }
            ForEach(layout.pieces) { piece in
                switch piece.kind {
                case .app(let app):
                    appSlice(app, width: piece.width, visible: visible)
                case .system(let watts):
                    SystemSlice(costDescription: costDescription(forWatts: watts), hide: hideSystem)
                        .frame(width: piece.width)
                        .transition(.opacity)
                }
            }
        }
        .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private func appSlice(_ app: AppUsage, width: CGFloat, visible: [AppUsage]) -> some View {
        AppSlice(
            app: app,
            costDescription: costDescription(forWatts: app.watts),
            isDragged: draggedApp == app.id,
            isKeyboardFocused: keyboardSlice == app.id,
            isInspected: inspectedApp == app.id,
            focusedApp: $focusedApp,
            draggedApp: $draggedApp,
            quit: quit,
            inspect: inspect,
            exclude: app.bundleIdentifier == nil ? nil : exclude
        )
        .frame(width: width)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedSlice, equals: app.id)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard keyboardSlice == app.id else { return .ignored }
            confirmQuit(app)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard let index = visible.firstIndex(where: { $0.id == app.id }) else { return .ignored }
            let next = press.key == .leftArrow ? index - 1 : index + 1
            guard visible.indices.contains(next) else { return .ignored }
            focusedSlice = visible[next].id
            keyboardSlice = visible[next].id
            return .handled
        }
        .onKeyPress(keys: [.return, .space]) { _ in
            guard keyboardSlice == app.id else { return .ignored }
            inspect(app)
            return .handled
        }
        .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsChargingAnimation: Bool {
        // Like the menu bar's glint: none in Low Power Mode, where every bit of energy counts.
        animatesCharging && snapshot.isCharging && !reduceMotion && !snapshot.isLowPowerModeOn
    }

    /// White light on a dark or green battery; a green wave on a white one, where white light wouldn't show.
    private var waveColor: Color {
        baseFill == .white ? Color(red: 0.2, green: 0.78, blue: 0.35) : .white
    }

    /// Like the menu bar icon: white on dark, near-black on light. Green while
    /// charging and red when low, if colours are on.
    private var baseFill: Color {
        if usesColor {
            switch snapshot.chargeState {
            case .charging: return Color(red: 0.2, green: 0.78, blue: 0.35)
            case .discharging where snapshot.percentage <= BatteryIcon.lowPercentage: return Color(red: 0.95, green: 0.27, blue: 0.23)
            default: break
            }
        }
        return colorScheme == .dark ? .white : Color(white: 0.12)
    }

    /// The label is dark only on the white fill of dark mode.
    private var labelColor: Color {
        baseFill == .white ? Color.black.opacity(0.85) : .white
    }

    private var centerText: some View {
        HStack(spacing: 4) {
            if snapshot.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .modifier(ChargingGlow(color: baseFill == .white ? waveColor : .white))
            } else if snapshot.chargeState == .notCharging {
                Image(systemName: "powerplug.fill").font(.system(size: 17, weight: .semibold))
            }
            Text(centerString)
                .font(.system(size: 24, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(labelColor)
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

    private func costLabels(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.pieces) { piece in
                Group {
                    switch piece.kind {
                    case .app(let app):
                        Text(costText(forWatts: app.watts))
                            .foregroundStyle(focusedApp?.id == app.id || inspectedApp == app.id ? .primary : .secondary)
                            .opacity(draggedApp == app.id ? 0 : 1)
                    case .system(let watts):
                        Text(costText(forWatts: watts))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: piece.width)
                .offset(x: piece.offset)
            }
        }
        .allowsHitTesting(false)
    }

    /// What VoiceOver reads for a slice: "costs 48 minutes", or its power draw on the adapter.
    private func costDescription(forWatts watts: Double) -> String {
        if estimates.appliesToTime {
            let cost = estimates.timeGained(byQuitting: watts)
            guard cost >= 60 else { return String(localized: "costs less than a minute") }
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.allowedUnits = cost >= 3600 ? [.hour, .minute] : [.minute]
            return String(localized: "costs \(formatter.string(from: (cost / 60).rounded() * 60) ?? "")")
        }
        let formatted = watts.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "uses \(formatted) watts")
    }

    private func costText(forWatts watts: Double) -> String {
        if estimates.appliesToTime {
            let cost = estimates.timeGained(byQuitting: watts)
            return cost >= 60 ? TimeFormat.cost(cost) : "<1m"
        }
        // "0.0 W" would read as nothing at all; the app is using something, just not much.
        guard watts >= 0.05 else { return "<" + (0.1).formatted(.number.precision(.fractionLength(1))) + " W" }
        return watts.formatted(.number.precision(.fractionLength(1))) + " W"
    }
}

/// One app's slice: its colour, its icon, and the drag that quits it.
private struct AppSlice: View {
    let app: AppUsage
    let costDescription: String
    let isDragged: Bool
    let isKeyboardFocused: Bool
    /// Its processes are listed under the battery.
    let isInspected: Bool
    @Binding var focusedApp: AppUsage?
    @Binding var draggedApp: AppUsage.ID?
    let quit: (AppUsage) -> Void
    let inspect: (AppUsage) -> Void
    let exclude: ((AppUsage) -> Void)?

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
                .scaleEffect(isHovered || isKeyboardFocused ? 1.12 : 1)
                .opacity(isDragged ? 0 : 1)
        }
        // The keyboard focus ring, drawn inside the slice so the pill's rounded clip doesn't cut it off.
        // Selected: its processes are listed below, so it keeps the hover's lift.
        .overlay {
            if isInspected && !isKeyboardFocused && !isHovered {
                Rectangle().fill(.white.opacity(0.16)).transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: isInspected)
        .overlay {
            if isKeyboardFocused {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .overlay(Rectangle().strokeBorder(.white.opacity(0.7), lineWidth: 1).padding(2.5))
            }
        }
        .animation(.snappy(duration: 0.18), value: isKeyboardFocused)
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
        .simultaneousGesture(TapGesture().onEnded { inspect(app) })
        .contextMenu {
            Button("Show Processes") { inspect(app) }
            Divider()
            Button("Quit \(app.name)") { quit(app) }
            Button("Show \(app.name)") {
                NSRunningApplication(processIdentifier: app.id)?.activate()
            }
            if let exclude {
                Divider()
                Button("Don't Show \(app.name) in the Battery") { exclude(app) }
            }
        }
        .help(app.name)
        .accessibilityElement()
        .accessibilityLabel(app.name)
        .accessibilityValue(costDescription)
        .accessibilityHint("Click to see its processes. Drag out of the panel, or press Delete, to quit")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Quit \(app.name)") { quit(app) }
        .accessibilityAction(named: "Show \(app.name)") { NSRunningApplication(processIdentifier: app.id)?.activate() }
        .accessibilityAction(named: "Show Processes") { inspect(app) }
    }

    /// Starts the drag; `DragToQuitController` follows it from there and reports how it ended.
    private var dragToQuit: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                let controller = DragToQuitController.shared
                guard !controller.isDragging, draggedApp == nil else { return }
                let panelFrame = NSApp.windows.lazy.compactMap { $0 as? BatteryPanel }.first?.cardFrame ?? .zero
                let app = app
                controller.begin(app, at: NSEvent.mouseLocation, panelFrame: panelFrame) { quits in
                    NSCursor.arrow.set()
                    if quits { quit(app) }
                    withAnimation(.snappy(duration: 0.25).delay(quits ? 0 : 0.18)) { draggedApp = nil }
                    focusedApp = nil
                }
                NSCursor.closedHand.set()
                withAnimation(.snappy(duration: 0.2)) { draggedApp = app.id }
                focusedApp = app
            }
    }
}

/// The slice for what no app accounts for: the display (usually most of it), graphics, Wi‑Fi and Bluetooth, and
/// macOS itself. It can't be quit, so it can't be dragged; turning the brightness down is what shrinks it.
private struct SystemSlice: View {
    let costDescription: String
    let hide: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(colorScheme == .dark ? 0.5 : 0.38))
            Image(systemName: "sun.max.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.15)).frame(width: 1)
        }
        .contentShape(.rect)
        .contextMenu {
            Button("Displays Settings…") { SystemSettings.open(.displays) }
            if let hide {
                Divider()
                Button("Don't Show Display & System in the Battery") { hide() }
            }
        }
        .help("Display & System: the screen, graphics, Wi‑Fi, Bluetooth and macOS itself. A dimmer screen makes it smaller.")
        .accessibilityElement()
        .accessibilityLabel("Display and system")
        .accessibilityValue(costDescription)
    }
}
