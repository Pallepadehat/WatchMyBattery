#if DEBUG
    import AppKit
    import BatteryKit
    import SwiftUI

    /// Renders the panel and menu bar icons to PNG files, for checking the
    /// design without clicking around: `WatchMyBattery --render-previews <folder>`.
    enum PreviewRenderer {
        static func runIfRequested() {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "--render-previews"), arguments.indices.contains(index + 1) else { return }
            let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            render(to: folder)
            exit(0)
        }

        private static let sampleApps: [(path: String, watts: Double)] = [
            ("/Applications/Xcode.app", 2.6),
            ("/System/Applications/Music.app", 1.4),
            ("/Applications/Safari.app", 0.9),
            ("/System/Applications/Messages.app", 0.3),
            ("/System/Applications/Notes.app", 0.1),
        ]

        private static func render(to folder: URL) {
            let apps = sampleApps.enumerated().map { index, sample in
                let icon = NSWorkspace.shared.icon(forFile: sample.path)
                return AppUsage(
                    id: pid_t(1000 + index), name: FileManager.default.displayName(atPath: sample.path).replacingOccurrences(of: ".app", with: ""),
                    bundleIdentifier: nil, icon: icon, tint: IconTint.color(of: icon), watts: sample.watts)
            }
            let states: [(String, BatterySnapshot)] = [
                ("discharging", BatterySnapshot(percentage: 64, powerSource: .battery, chargeState: .discharging, timeRemaining: 4 * 3600 + 50 * 60)),
                ("low", BatterySnapshot(percentage: 12, powerSource: .battery, chargeState: .discharging, timeRemaining: 52 * 60)),
                ("charging", BatterySnapshot(percentage: 81, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 35 * 60)),
                ("half", BatterySnapshot(percentage: 41, powerSource: .battery, chargeState: .discharging, timeRemaining: 2 * 3600 + 5 * 60)),
                ("full", BatterySnapshot(percentage: 100, powerSource: .powerAdapter, chargeState: .charged, timeRemaining: nil)),
            ]

            let health = BatteryHealth(condition: .normal, maximumCapacity: 0.88, cycleCount: 564)
            for (name, snapshot) in states {
                for scheme in [ColorScheme.dark, .light] {
                    let model = AppModel(settings: previewSettings())
                    model.settings.showsReplaceTip = false
                    model.battery.preview(
                        snapshot, health: name == "low" ? BatteryHealth(condition: .serviceRecommended, maximumCapacity: 0.74, cycleCount: 1012) : health)
                    model.usage.preview(
                        apps: Array(apps.prefix(model.settings.maximumApps)), systemWatts: 14,
                        refusal: name == "half" ? QuitRefusal(id: apps[1].id, name: apps[1].name, icon: apps[1].icon) : nil)
                    let view = BatteryPanelView(model: model, close: {})
                        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.94))
                        .clipShape(.rect(cornerRadius: 16))
                        .padding(30)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.2, blue: 0.75), Color(red: 0.25, green: 0.1, blue: 0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .environment(\.colorScheme, scheme)
                    save(view, to: folder.appending(path: "panel-\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }

            // Menu bar icons, every state and style, on a dark and a light bar.
            let settings = AppSettings(defaults: UserDefaults(suiteName: "preview")!)
            var rows: [AnyView] = []
            for style in PercentageStyle.allCases {
                settings.percentageStyle = style
                for usesColor in [true, false] {
                    settings.usesColor = usesColor
                    let snapshots = [
                        BatterySnapshot(percentage: 100, powerSource: .powerAdapter, chargeState: .charged, timeRemaining: nil),
                        BatterySnapshot(percentage: 64, powerSource: .battery, chargeState: .discharging, timeRemaining: 3600),
                        BatterySnapshot(percentage: 35, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600),
                        BatterySnapshot(percentage: 80, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil),
                        BatterySnapshot(percentage: 9, powerSource: .battery, chargeState: .discharging, timeRemaining: 600),
                        BatterySnapshot(
                            percentage: 50, powerSource: .battery, chargeState: .discharging, timeRemaining: 600, isLowPowerModeOn: true),
                    ]
                    for dark in [true, false] {
                        let icons = snapshots.map { snapshot in
                            var icon = BatteryIcon(snapshot: snapshot, settings: settings)
                            icon.drawsForDarkBar = dark
                            return icon.image()
                        }
                        rows.append(
                            AnyView(
                                HStack(spacing: 18) {
                                    ForEach(icons.indices, id: \.self) { index in
                                        Image(nsImage: icons[index]).renderingMode(icons[index].isTemplate ? .template : .original)
                                    }
                                }
                                .foregroundStyle(dark ? .white : .black)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(dark ? Color(white: 0.15) : Color(white: 0.88))
                                .environment(\.colorScheme, dark ? .dark : .light)
                            ))
                    }
                }
            }
            save(VStack(spacing: 0) { ForEach(rows.indices, id: \.self) { rows[$0] } }.frame(width: 340), to: folder.appending(path: "icons.png"))

            // The charging glint, frame by frame, in every style.
            var glintRows: [AnyView] = []
            let charging = BatterySnapshot(percentage: 45, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600)
            for (style, usesColor) in [(PercentageStyle.hidden, true), (.hidden, false), (.inside, true), (.inside, false)] {
                for dark in [true, false] {
                    let frames = stride(from: 0, to: ChargingAnimator.framesPerSweep, by: 3).map { frame in
                        var icon = BatteryIcon(snapshot: charging, percentageStyle: style, usesColor: usesColor)
                        icon.chargeGlint = Double(frame) / Double(ChargingAnimator.framesPerSweep - 1)
                        icon.drawsForDarkBar = dark
                        return icon.image()
                    }
                    glintRows.append(
                        AnyView(
                            HStack(spacing: 10) {
                                ForEach(frames.indices, id: \.self) { index in
                                    Image(nsImage: frames[index]).renderingMode(frames[index].isTemplate ? .template : .original)
                                }
                            }
                            .foregroundStyle(dark ? .white : .black)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(dark ? Color(white: 0.15) : Color(white: 0.88))
                            .environment(\.colorScheme, dark ? .dark : .light)
                        ))
                }
            }
            save(
                VStack(spacing: 0) { ForEach(glintRows.indices, id: \.self) { glintRows[$0] } }.frame(width: 340),
                to: folder.appending(path: "glint.png"))
        }

        /// Settings kept apart from the real app's, so rendering previews never changes them.
        private static func previewSettings() -> AppSettings {
            let defaults = UserDefaults(suiteName: "WatchMyBattery.previews")!
            defaults.removePersistentDomain(forName: "WatchMyBattery.previews")
            return AppSettings(defaults: defaults)
        }

        private static func save(_ view: some View, to url: URL) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            // The renderer hands back an HDR image; flatten it to plain sRGB so it looks right anywhere.
            guard let image = renderer.cgImage,
                let context = CGContext(
                    data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage(),
                let png = NSBitmapImageRep(cgImage: flattened).representation(using: .png, properties: [:])
            else { return }
            try? png.write(to: url)
        }
    }
#endif
