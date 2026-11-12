import BatteryKit
import SwiftUI

/// The panel's accessories: each connected one with the battery of every
/// part, like the batteries in the system's Bluetooth menu.
struct AccessoriesSection: View {
    let accessories: [Accessory]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accessories")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 7) {
                ForEach(accessories) { accessory in
                    AccessoryRow(accessory: accessory)
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

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                icon
                name.fixedSize()
                Spacer(minLength: 10)
                levels
            }
            HStack(alignment: .top, spacing: 9) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    name
                    levels
                }
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 24)
        .animation(.snappy(duration: 0.3), value: accessory.displayParts)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessory.name)
        .accessibilityValue(accessory.displayParts.map(\.spokenDescription).joined(separator: ", "))
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
            .truncationMode(.middle)
    }

    private var levels: some View {
        HStack(spacing: 10) {
            ForEach(accessory.displayParts) { part in
                PartLevel(part: part, symbols: accessory.symbols, showsRole: accessory.parts.count > 1)
            }
        }
        .fixedSize()
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
