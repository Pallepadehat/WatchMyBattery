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
                // Optimized Battery Charging: on its way to 80%, and held there.
                ("optimized", BatterySnapshot(percentage: 64, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 22 * 60, chargeTarget: 80)),
                ("holding", BatterySnapshot(percentage: 80, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil, chargeTarget: 80)),
                // 0.2.5: the insights, and the history's ten days.
                ("insights", BatterySnapshot(percentage: 23, powerSource: .battery, chargeState: .discharging, timeRemaining: 70 * 60)),
                ("tendays", BatterySnapshot(percentage: 64, powerSource: .battery, chargeState: .discharging, timeRemaining: 4 * 3600 + 50 * 60)),
            ]

            let health = BatteryHealth(condition: .normal, maximumCapacity: 0.88, cycleCount: 564)
            for (name, snapshot) in states {
                for scheme in [ColorScheme.dark, .light] {
                    // In memory: previews must never open (or move) the real history.
                    let model = AppModel(settings: previewSettings(), history: HistoryRecorder(storeURL: nil, legacyFileURL: nil))
                    model.settings.showsReplaceTip = false
                    model.lowPowerMode.preview(isSupported: true)
                    model.battery.preview(
                        snapshot, health: name == "low" ? BatteryHealth(condition: .serviceRecommended, maximumCapacity: 0.74, cycleCount: 1012) : health)
                    model.usage.preview(
                        apps: Array(apps.prefix(model.settings.maximumApps)), systemWatts: 14,
                        refusal: name == "half" ? QuitRefusal(id: apps[1].id, name: apps[1].name, icon: apps[1].icon) : nil)
                    let history = sampleHistory(apps: sampleApps.map(\.path), now: snapshot)
                    model.history.preview(history, profile: sampleProfile(history: history))
                    if name == "tendays" { model.settings.historyRange = .tenDays }
                    if name == "insights" { previewInsights(model.insights, history: history) }
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
            let toFull = BatterySnapshot(percentage: 45, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600)
            // Charging to 80%: the glint settles at the target instead of running on to the terminal.
            let toTarget = BatterySnapshot(percentage: 45, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600, chargeTarget: 80)
            for (style, usesColor, charging) in [
                (PercentageStyle.hidden, true, toFull), (.hidden, false, toFull), (.inside, true, toFull), (.inside, false, toFull),
                (.hidden, true, toTarget),
            ] {
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

        /// A day that ends in `snapshot`: on battery overnight, charged in the morning, and unplugged two hours ago.
        private static func sampleHistory(apps paths: [String], now snapshot: BatterySnapshot) -> BatteryHistory {
            var history = BatteryHistory()
            let now = Date()
            func at(_ hoursAgo: Double) -> Date { now.addingTimeInterval(-hoursAgo * 3600) }
            func level(_ percentage: Int, pluggedIn: Bool) -> BatterySnapshot {
                BatterySnapshot(
                    percentage: percentage, powerSource: pluggedIn ? .powerAdapter : .battery,
                    chargeState: pluggedIn ? .charging : .discharging, timeRemaining: nil)
            }
            var hoursAgo = 23.5
            var percentage = 88
            // Evening and night on battery.
            while hoursAgo > 13 {
                history.record(level(percentage, pluggedIn: false), at: at(hoursAgo))
                percentage -= hoursAgo > 18 ? 3 : 1
                hoursAgo -= 0.5
            }
            // Charging in the morning.
            while hoursAgo > 10.5 {
                history.record(level(percentage, pluggedIn: true), at: at(hoursAgo))
                percentage = min(percentage + 12, 100)
                hoursAgo -= 0.25
            }
            // A while plugged in and full, then on battery down to now.
            history.record(level(100, pluggedIn: true), at: at(hoursAgo))
            let unplugged = snapshot.isPluggedIn ? 4.0 : 2.25
            hoursAgo = 7
            percentage = 100
            while hoursAgo > unplugged + 0.1 {
                history.record(level(percentage, pluggedIn: false), at: at(hoursAgo))
                percentage -= 4
                hoursAgo -= 0.4
            }
            history.record(level(percentage, pluggedIn: true), at: at(hoursAgo))
            percentage = 100
            history.record(level(100, pluggedIn: true), at: at(unplugged + 0.05))
            history.record(level(100, pluggedIn: snapshot.isPluggedIn), at: at(unplugged))
            let steps = 12
            for step in 1...steps {
                let fraction = Double(step) / Double(steps)
                let value = 100 - Int(Double(100 - snapshot.percentage) * fraction)
                history.record(level(value, pluggedIn: snapshot.isPluggedIn), at: at(unplugged * (1 - fraction) + 0.01))
            }

            let identities = paths.map { path in
                BatteryHistory.AppIdentity(
                    name: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""),
                    bundleIdentifier: Bundle(path: path)?.bundleIdentifier)
            }
            let watts = [3.1, 1.7, 0.9, 0.4, 0.2]
            for index in 0..<24 {
                var joules: [BatteryHistory.AppIdentity: Double] = [:]
                for (app, power) in zip(identities, watts) { joules[app] = power * 300 * (0.7 + 0.6 * Double((index * 7) % 5) / 4) }
                history.record(joules: joules, seconds: 300, systemWatts: 9, at: at(Double(24 - index) * 0.08))
            }
            return history
        }

        /// Ten days of use, ending with `history`'s last day.
        private static func sampleProfile(history: BatteryHistory) -> UsageProfile {
            var profile = UsageProfile()
            let now = Date()
            let used = [38, 52, 0, 61, 44, 27, 73, 49, 35]
            for (offset, drained) in used.enumerated() {
                let day = now.addingTimeInterval(-Double(10 - offset) * 24 * 3600)
                guard drained > 0 else { continue }
                profile.record(level: .init(date: day, percentage: 100, isPluggedIn: false))
                profile.record(level: .init(date: day.addingTimeInterval(Double(drained) * 300), percentage: 100 - drained, isPluggedIn: false))
                profile.record(level: .init(date: day.addingTimeInterval(Double(drained) * 300 + 60), percentage: 100 - drained, isPluggedIn: true))
            }
            for point in history.levels { profile.record(level: point) }
            for sample in history.samples {
                for day in 0..<9 {
                    let earlier = BatteryHistory.EnergySample(
                        date: sample.date.addingTimeInterval(-Double(day + 1) * 24 * 3600), seconds: sample.seconds,
                        joules: sample.joules.mapValues { $0 * Double(day % 3 + 1) }, systemWatts: sample.systemWatts)
                    profile.record(earlier, apps: history.apps)
                }
                profile.record(sample, apps: history.apps)
            }
            return profile
        }

        /// One of each insight.
        private static func previewInsights(_ insights: InsightsMonitor, history: BatteryHistory) {
            let now = Date()
            let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 1800).rounded(.up) * 1800 + 1800)
            let meeting = MeetingCheck.warning(
                snapshot: BatterySnapshot(percentage: 23, powerSource: .battery, chargeState: .discharging, timeRemaining: 70 * 60),
                events: [UpcomingEvent(start: start, end: start.addingTimeInterval(3600))], now: now, lead: 2 * 3600)
            let apps = history.appEnergy(since: now.addingTimeInterval(-BatteryHistory.retention))
            let figma = BatteryHistory.AppIdentity(name: "Music", bundleIdentifier: "com.apple.Music")
            let newApp = BatteryHistory.AppEnergy(app: figma, joules: 9000, batteryTime: 1000)
            insights.preview(
                meeting: meeting, unusualDrain: UnusualDrain(currentWatts: 13.2, usualWatts: 10, cause: apps.first?.app), newApps: [newApp])
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
