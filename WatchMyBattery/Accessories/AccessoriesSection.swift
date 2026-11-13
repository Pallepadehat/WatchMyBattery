import BatteryKit
import SwiftUI

/// The panel's accessories: each connected one with the battery of every
/// part, like the batteries in the system's Bluetooth menu.
struct AccessoriesSection: View {
    let accessories: [Accessory]
    let monitor: AccessoryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accessories")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 7) {
                ForEach(accessories) { accessory in
                    AccessoryRow(accessory: accessory, monitor: monitor)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

/// "AirPods Pro      L 82%  R 64%  ▢ 47%": the device, then each part's level.
/// When the levels don't fit beside the name, they go on a line under it.
struct AccessoryRow: View {
    let accessory: Accessory
    /// For an iPhone or iPad: how old its reading is, and refreshing it.
    var monitor: AccessoryMonitor?

    /// An iPhone or iPad out of reach, showing its last reading: when that was.
    private var staleSince: Date? { monitor?.staleReadDate(of: accessory) }
    private var isRefreshing: Bool { monitor?.isRefreshingDevices ?? false }
    /// A refresh just now couldn't reach it.
    private var isUnreachable: Bool { monitor?.unreachableDeviceIDs.contains(accessory.id) ?? false }

    var body: some View {
        // Each minute, so a reading turns old, and says how old, while the panel is open.
        TimelineView(.everyMinute) { _ in
            row
        }
        .frame(minHeight: 24)
        .animation(.snappy(duration: 0.3), value: accessory.displayParts)
        .animation(.snappy(duration: 0.3), value: staleSince == nil)
        .animation(.easeInOut(duration: 0.18), value: isRefreshing)
        .animation(.easeInOut(duration: 0.18), value: isUnreachable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessory.name)
        .accessibilityValue(spokenValue)
    }

    @ViewBuilder private var row: some View {
        if staleSince != nil {
            staleRow
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    icon
                    name.fixedSize()
                    Spacer(minLength: 10)
                    levels
                }
                HStack(spacing: 9) {
                    icon
                    VStack(alignment: .leading, spacing: 3) {
                        name
                        levels
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// An old reading:
    ///
    ///     Kim's iPhone 17 Pro Max         ◯ 71 %
    ///     31 min. ago · ↻ Refresh
    private var staleRow: some View {
        HStack(spacing: 9) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    name
                    Spacer(minLength: 8)
                    levels
                }
                statusLine
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
    }

    private var spokenValue: String {
        let levels = accessory.displayParts.map(\.spokenDescription).joined(separator: ", ")
        guard let staleSince else { return levels }
        return levels + ", " + String(localized: "read \(staleSince.formatted(.relative(presentation: .named)))")
    }

    /// Under an old reading: when it was read (or that a refresh couldn't reach it), and a way to read it again.
    private var statusLine: some View {
        HStack(spacing: 5) {
            if isRefreshing {
                Spinner()
                    .frame(width: 9, height: 9)
                    .foregroundStyle(.secondary)
                Text("Reading…")
                    .foregroundStyle(.secondary)
            } else {
                if isUnreachable {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Couldn’t reach it")
                        .foregroundStyle(.orange)
                } else if let staleSince {
                    Text(staleSince, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .foregroundStyle(.tertiary)
                }
                if let monitor {
                    Text(verbatim: "·").foregroundStyle(.quaternary)
                    Button {
                        monitor.refreshDevices()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .imageScale(.small)
                    }
                    .buttonStyle(InlineLinkButtonStyle())
                    .help("Read it again. It needs to be awake and on the same Wi‑Fi.")
                }
            }
        }
        .transition(.opacity)
        .id(isRefreshing ? "reading" : isUnreachable ? "unreachable" : "stale")
    }

    /// The device's symbol on a small tile, like the icons in the system's Bluetooth menu.
    private var icon: some View {
        Image(systemName: accessory.symbols.device)
            .font(.system(size: 12))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .background(.primary.opacity(0.08), in: .circle)
    }

    private var name: some View {
        Text(accessory.name)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var levels: some View {
        HStack(spacing: 10) {
            ForEach(accessory.displayParts) { part in
                PartLevel(part: part, symbols: accessory.symbols, showsRole: accessory.parts.count > 1)
            }
        }
        .fixedSize()
        // An old reading: there, but not to be relied on.
        .opacity(staleSince == nil ? 1 : 0.55)
    }
}

/// A small text button, like a link: secondary until the pointer is over it, with a soft capsule behind it then.
private struct InlineLinkButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.primary.opacity(configuration.isPressed ? 0.14 : isHovering ? 0.07 : 0), in: .capsule)
            .padding(.horizontal, -5)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// A small spinning arc, drawn in SwiftUI: AppKit's spinner complains about its size while it animates in a list.
private struct Spinner: View {
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.88)
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
    }
}

/// One part's level: a small ring, which part it is, and the percentage.
private struct PartLevel: View {
    let part: Accessory.Part
    let symbols: AccessorySymbols
    /// Say which part this is: there are several.
    let showsRole: Bool

    var body: some View {
        HStack(spacing: 4) {
            LevelRing(level: part.level, color: AccessoryColor.of(part), lineWidth: 2.4)
                .frame(width: 13, height: 13)
                .overlay {
                    if part.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 6.5, weight: .black))
                            .foregroundStyle(AccessoryColor.green)
                    }
                }
            if showsRole {
                roleLabel
                    .foregroundStyle(.tertiary)
            }
            Text(part.level, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(part.isLow ? AnyShapeStyle(AccessoryColor.red) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText(value: part.level))
        }
        .help(part.spokenDescription)
    }

    @ViewBuilder private var roleLabel: some View {
        switch part.role {
        case .left: Text("L", comment: "Short for the left earbud").font(.system(size: 10, weight: .semibold))
        case .right: Text("R", comment: "Short for the right earbud").font(.system(size: 10, weight: .semibold))
        case .case: Image(systemName: symbols.case).font(.system(size: 10))
        case .both, .single: EmptyView()
        }
    }
}
