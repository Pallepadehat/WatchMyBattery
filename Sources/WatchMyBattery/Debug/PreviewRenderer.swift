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

        /// Last night's sleep, a few before it, and Music keeping the Mac awake.
        private static func previewSleep(_ sleep: SleepMonitor, now: Date) {
            let morning = Calendar.current.startOfDay(for: now).addingTimeInterval(7 * 3600 + 20 * 60)
            var log = SleepLog()
            for (day, used) in [(3, 6), (2, 5), (1, 21)] {
                let end = morning.addingTimeInterval(-Double(day - 1) * 24 * 3600)
                log.record(
                    SleepSession(start: end.addingTimeInterval(-8.2 * 3600), end: end, startLevel: 92, endLevel: 92 - used, wasPluggedIn: false),
                    now: now)
            }
            sleep.preview(
                log,
                holders: [
                    AwakeHolder(
                        id: "com.apple.Music", name: "Music", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app"),
                        reasons: [String(localized: "Playing audio")], effect: .keepsSystemAwake, since: now.addingTimeInterval(-40 * 60),
                        activity: .audio)
                ])
        }

        private static func render(to folder: URL) {
            renderOnboarding(to: folder)
            renderVitals(to: folder)
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
                // 0.3.0: held at a charge limit, and a slice's processes with the last sleep.
                (
                    "limit",
                    BatterySnapshot(
                        percentage: 85, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil, chargeTarget: 85,
                        targetReason: .chargeLimit)
                ),
                ("care", BatterySnapshot(percentage: 58, powerSource: .battery, chargeState: .discharging, timeRemaining: 3 * 3600 + 40 * 60)),
                // A screen too short for all of it, so the middle scrolls (scrolled a little, to show the fades).
                ("short", BatterySnapshot(percentage: 9, powerSource: .battery, chargeState: .discharging, timeRemaining: 11 * 3600 + 31 * 60)),
                // 0.4.0: why charging is paused or slow, with the charger.
                ("weakcharger", BatterySnapshot(percentage: 47, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil)),
                ("slowcharger", BatterySnapshot(percentage: 47, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3 * 3600)),
                ("hot", BatterySnapshot(percentage: 62, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil)),
                ("nearlyfull", BatterySnapshot(percentage: 97, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil)),
                // 0.4.4: commands and background programs get slices of their own.
                ("tools", BatterySnapshot(percentage: 58, powerSource: .battery, chargeState: .discharging, timeRemaining: 3 * 3600 + 10 * 60)),
                ("toolsspotlight", BatterySnapshot(percentage: 58, powerSource: .battery, chargeState: .discharging, timeRemaining: 3 * 3600 + 10 * 60)),
                ("toolssystem", BatterySnapshot(percentage: 58, powerSource: .battery, chargeState: .discharging, timeRemaining: 3 * 3600 + 10 * 60)),
                // 0.4.4: a big charger giving the Mac too little, so the battery makes up the rest.
                ("underpowered", BatterySnapshot(percentage: 95, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil)),
                // 0.4.3: an app's history opened in the last day, and a day picked in the last ten.
                ("historyapp", BatterySnapshot(percentage: 64, powerSource: .battery, chargeState: .discharging, timeRemaining: 4 * 3600 + 50 * 60)),
                ("historyday", BatterySnapshot(percentage: 64, powerSource: .battery, chargeState: .discharging, timeRemaining: 4 * 3600 + 50 * 60)),
            ]
            /// The charger in each 0.4.0 state, what the Mac draws, and what comes in from the charger.
            let chargers: [String: (adapter: PowerAdapter, systemWatts: Double, chargerWatts: Double)] = [
                "weakcharger": (PowerAdapter(watts: 30, name: "30W USB-C Power Adapter"), 34, 29),
                "slowcharger": (PowerAdapter(watts: 30, name: "30W USB-C Power Adapter"), 24, 29),
                "hot": (PowerAdapter(watts: 96, name: "96W USB-C Power Adapter"), 14, 14),
                "nearlyfull": (PowerAdapter(watts: 96, name: "96W USB-C Power Adapter"), 9, 9),
                "charging": (PowerAdapter(watts: 70, name: "70W USB-C Power Adapter"), 14, 42),
                "underpowered": (PowerAdapter(watts: 100, name: "100W USB-C Power Adapter"), 6.6, 4.5),
            ]

            let health = BatteryHealth(condition: .normal, maximumCapacity: 0.88, cycleCount: 564)
            for (name, snapshot) in states {
                for scheme in [ColorScheme.dark, .light] {
                    // In memory: previews must never open (or move) the real history.
                    let model = AppModel(settings: previewSettings(), history: HistoryRecorder(storeURL: nil, legacyFileURL: nil))
                    model.settings.showsReplaceTip = false
                    model.lowPowerMode.preview(isSupported: true)
                    let charger = chargers[name]
                    model.battery.preview(
                        snapshot, health: name == "low" ? BatteryHealth(condition: .serviceRecommended, maximumCapacity: 0.74, cycleCount: 1012) : health,
                        readings: BatteryReadings(
                            temperature: name == "hot" ? 42.3 : name == "charging" ? 36.4 : 29.6, voltage: 12.41,
                            current: snapshot.isCharging ? 2.35 : name == "weakcharger" || name == "underpowered" ? -0.4 : snapshot.isPluggedIn ? 0 : -1.12),
                        adapter: charger?.adapter)
                    model.chargeLimit.preview(limit: name == "limit" ? 85 : name == "charging" ? 100 : 80)
                    let tools = Self.sampleTools()
                    model.usage.preview(
                        apps: Array((name.hasPrefix("tools") ? tools + apps : apps).prefix(model.settings.maximumApps)),
                        systemWatts: charger?.systemWatts ?? 14,
                        chargerWatts: charger?.chargerWatts,
                        refusal: name == "half" ? QuitRefusal(id: apps[1].id, name: apps[1].name, icon: apps[1].icon) : nil)
                    let history = sampleHistory(apps: sampleApps.map(\.path), now: snapshot)
                    model.history.preview(history, profile: sampleProfile(history: history))
                    if name == "tendays" { model.settings.historyRange = .tenDays }
                    HistorySection.previewState = (nil, nil)
                    if name == "historyapp" || name == "historyday" {
                        let made = PretendHistory.make(days: 30)
                        model.history.preview(made.history, profile: made.profile)
                        let calendar = Calendar.current
                        let day = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: Date()))
                        if name == "historyday" { model.settings.historyRange = .tenDays }
                        HistorySection.previewState = (name == "historyday" ? day : nil, "com.apple.dt.Xcode")
                    }
                    if name == "insights" { previewInsights(model.insights, history: history) }
                    if name == "discharging" || name == "charging" || name == "short" { model.accessories.preview(AccessoryMonitor.samples) }
                    if name == "short" {
                        model.panelMaxHeight = 560
                        previewSleep(model.sleep, now: Date())
                    }
                    if name == "discharging" {
                        // An iPhone out of reach with a long name: its last reading, from a while ago.
                        model.accessories.preview(
                            AccessoryMonitor.samples.dropLast() + [
                                Accessory(
                                    id: "device:iphone", name: "Kim’s iPhone 17 Pro Max", kind: .phone,
                                    parts: [.init(role: .single, percentage: 71)], vendorID: 0x004C)
                            ],
                            readDates: ["device:iphone": Date.now.addingTimeInterval(-31 * 60)])
                    }
                    // A refresh reading the iPhone.
                    if name == "half" {
                        model.accessories.preview(
                            [
                                Accessory(
                                    id: "device:ipad", name: "iPad Air", kind: .tablet,
                                    parts: [.init(role: .single, percentage: 38)], vendorID: 0x004C)
                            ],
                            readDates: ["device:ipad": Date.now.addingTimeInterval(-3 * 60 * 60)])
                        model.accessories.preview(refreshing: true)
                    }
                    // A refresh that couldn't reach the iPhone, as it says so in the row.
                    if name == "charging" {
                        model.accessories.preview(
                            AccessoryMonitor.samples.dropLast() + [
                                Accessory(
                                    id: "device:iphone", name: "iPhone", kind: .phone,
                                    parts: [.init(role: .single, percentage: 54)], vendorID: 0x004C)
                            ],
                            readDates: ["device:iphone": Date.now.addingTimeInterval(-2 * 60 * 60)])
                        model.accessories.preview(unreachable: ["device:iphone"])
                    }
                    if name == "care" || name == "limit" { previewSleep(model.sleep, now: Date()) }
                    if name == "care" {
                        model.usage.preview(
                            inspecting: apps[0].id,
                            processes: [
                                ProcessEnergy(pid: 1000, name: "Xcode", watts: 1.1, isApp: true),
                                ProcessEnergy(pid: 2001, name: "SourceKitService", watts: 0.8, isApp: false),
                                ProcessEnergy(pid: 2002, name: "swift-frontend", watts: 0.5, isApp: false),
                                ProcessEnergy(pid: 2003, name: "com.apple.dt.SKAgent", watts: 0.2, isApp: false),
                            ])
                    }
                    if name == "toolsspotlight" {
                        model.usage.preview(
                            inspecting: 2002,
                            processes: [
                                ProcessEnergy(pid: 2002, name: "mds_stores", watts: 0.9, isApp: true, isEstimated: true),
                                ProcessEnergy(pid: 2003, name: "mdworker_shared", watts: 0.5, isApp: true),
                                ProcessEnergy(pid: 2006, name: "mds", watts: 0.2, isApp: true, isEstimated: true),
                            ])
                    }
                    if name == "toolssystem" {
                        model.usage.preview(
                            system: SystemBreakdown(
                                processes: [
                                    ProcessEnergy(pid: 398, name: "runningboardd", watts: 0.21, isApp: true, isEstimated: true),
                                    ProcessEnergy(pid: 325, name: "launchd", watts: 0.06, isApp: true, isEstimated: true),
                                    ProcessEnergy(pid: 330, name: "fseventsd", watts: 0.04, isApp: true, isEstimated: true),
                                ], hardwareWatts: 5.4))
                    }
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
                    let url = folder.appending(path: "panel-\(name)-\(scheme == .dark ? "dark" : "light").png")
                    // ImageRenderer can't draw a scroll view, so the capped panel is drawn in a window instead.
                    if model.panelMaxHeight.isFinite { saveInWindow(view, scheme: scheme, scrolledBy: 120, to: url) } else { save(view, to: url) }
                }
            }

            // The AirPods card, for a few kinds of headphones, in dark and light.
            let cards: [Accessory] = [
                AccessoryMonitor.samples[0],
                Accessory(
                    id: "a", name: "Patrick’s AirPods", kind: .earbuds,
                    parts: [.init(role: .left, percentage: 100), .init(role: .right, percentage: 97), .init(role: .case, percentage: 12)],
                    productID: 0x201B, vendorID: 0x004C),
                Accessory(
                    id: "b", name: "AirPods Max", kind: .headphones, parts: [.init(role: .single, percentage: 38, isCharging: true)],
                    productID: 0x201F, vendorID: 0x004C),
                Accessory(
                    id: "c", name: "Gym", kind: .earbuds,
                    parts: [.init(role: .left, percentage: 9), .init(role: .right, percentage: 26), .init(role: .case, percentage: 55)],
                    productID: 0x201D, vendorID: 0x004C),
                Accessory(
                    id: "d", name: "Beats Studio Pro", kind: .headphones, parts: [.init(role: .single, percentage: 72)], productID: 0x2017,
                    vendorID: 0x004C),
            ]
            for scheme in [ColorScheme.dark, .light] {
                let sheet = VStack(spacing: 22) {
                    ForEach(cards) { accessory in
                        AccessoryCard(accessory: accessory, fillsOnAppear: false)
                            .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.96))
                            .clipShape(.rect(cornerRadius: AccessoryCardWindow.cornerRadius, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                    }
                }
                .padding(30)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.2, blue: 0.75), Color(red: 0.25, green: 0.1, blue: 0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .environment(\.colorScheme, scheme)
                save(sheet, to: folder.appending(path: "card-\(scheme == .dark ? "dark" : "light").png"))

                // One card on its own, for the README.
                let single = AccessoryCard(accessory: cards[0], fillsOnAppear: false)
                    .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.96))
                    .clipShape(.rect(cornerRadius: AccessoryCardWindow.cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                    .padding(30)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.2, blue: 0.75), Color(red: 0.25, green: 0.1, blue: 0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .environment(\.colorScheme, scheme)
                save(single, to: folder.appending(path: "airpods-card-\(scheme == .dark ? "dark" : "light").png"))
            }

            // Menu bar icons, every state and style, on a dark and a light bar.
            let iconStyles: [(MenuBarIconStyle, insidePercentage: Bool)] = [(.battery, false), (.battery, true), (.ring, false), (.textOnly, false)]
            let settings = AppSettings(defaults: UserDefaults(suiteName: "preview")!)
            // Text only shows the percentage; the others just the icon, to see it on its own.
            settings.menuBarLabel = .none
            var rows: [AnyView] = []
            for (style, inside) in iconStyles {
                settings.menuBarIconStyle = style
                settings.showsPercentageInside = inside
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
                        let items = snapshots.map { MenuBarItem(snapshot: $0, settings: settings, watts: nil, drawsForDarkBar: dark) }
                        rows.append(
                            AnyView(
                                HStack(spacing: 18) {
                                    ForEach(items.indices, id: \.self) { index in
                                        MenuBarItemView(item: items[index])
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
            save(VStack(spacing: 0) { ForEach(rows.indices, id: \.self) { rows[$0] } }.frame(width: 400), to: folder.appending(path: "icons.png"))

            // Every motion, frame by frame: in the battery (coloured and not) and the ring, on a dark and a light bar.
            var glintRows: [AnyView] = []
            let charging = BatterySnapshot(percentage: 45, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600)
            // Charging to 80%: the glint settles at the target instead of running on to the terminal.
            let toTarget = BatterySnapshot(percentage: 45, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 3600, chargeTarget: 80)
            let trickling = BatterySnapshot(percentage: 77, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 600, chargeTarget: 80)
            let holding = BatterySnapshot(percentage: 80, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil, chargeTarget: 80)
            let motions: [(BatterySnapshot, MenuBarMotion)] = [
                (charging, .flow(level: 0.45, target: 1)), (toTarget, .flow(level: 0.45, target: 0.8)), (charging, .liquid), (charging, .stripes),
                (trickling, .calmLiquid), (trickling, .slowPulse), (holding, .stillWater), (holding, .heartbeat), (holding, .breathing),
            ]
            for (snapshot, motion) in motions {
                for (style, usesColor, dark) in [(MenuBarIconStyle.battery, true, true), (.battery, false, false), (.ring, true, true)] {
                    let phases = stride(from: 0, to: 1, by: 1.0 / 9).map { $0 }
                    let frames = phases.map { phase in
                        var icon = BatteryIcon(snapshot: snapshot, style: style, usesColor: usesColor, drawsForDarkBar: dark)
                        icon.motion = motion
                        icon.animationPhase = phase
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

        /// Every step of the welcome tour, settled, in light and dark.
        /// 0.4.4: what a busy developer's Mac shows: a command in a terminal, Spotlight indexing, Docker's engine and a
        /// server with no icon of its own.
        private static func sampleTools() -> [AppUsage] {
            let terminal = NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app")
            let program = NSWorkspace.shared.icon(forFile: "/bin/zsh")
            let spotlight = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Spotlight.app")
            // Docker's icon where it's installed; Xcode's otherwise, to show an app's icon on a program.
            let docker = NSWorkspace.shared.icon(
                forFile: FileManager.default.fileExists(atPath: "/Applications/Docker.app") ? "/Applications/Docker.app" : "/Applications/Xcode.app")
            return [
                AppUsage(
                    id: 2001, name: "cargo", bundleIdentifier: nil, icon: terminal, tint: ProgramTint.color(for: "cargo"), watts: 3.1,
                    kind: .program, isCommand: true, detail: "Running in Terminal. Quit stops it, like Ctrl-C."),
                AppUsage(
                    id: 2002, name: String(localized: "Spotlight"), bundleIdentifier: nil, icon: spotlight,
                    tint: IconTint.color(of: spotlight), watts: 1.6, kind: .macOS,
                    detail: MacOSServices.all.first?.detail, members: [2002, 2003]),
                AppUsage(
                    id: 2004, name: "Docker", bundleIdentifier: nil, icon: docker, tint: IconTint.color(of: docker), watts: 1.1,
                    kind: .program),
                AppUsage(
                    id: 2005, name: "postgres", bundleIdentifier: nil, icon: program, tint: ProgramTint.color(for: "postgres"), watts: 0.6,
                    kind: .program),
            ]
        }

        /// Settings › Battery Health, with months of made-up vitals, in dark and light: its list (also narrow), temperature
        /// over a month compared with the month before, power through the day on battery only (also narrow, over time),
        /// and a year of health.
        private static func renderVitals(to folder: URL) {
            let states: [(name: String, page: VitalsPage?, days: Int, compares: Bool, filter: VitalsFilter, throughTheDay: Bool)] = [
                ("list", nil, 7, false, .all, false), ("narrow", nil, 7, false, .all, false), ("narrowpower", .power, 30, true, .all, false),
                ("temperature", .temperature, 30, true, .all, false),
                // Just started: a few readings close together, and one health reading. Nothing should read "30–30".
                ("fresh", .temperature, 7, true, .all, false), ("freshlist", nil, 7, false, .all, false),
                ("power", .power, 30, false, .onBattery, true), ("health", .health, 365, false, .all, false),
            ]
            for scheme in [ColorScheme.dark, .light] {
                for state in states {
                    let model = AppModel(settings: previewSettings(), history: HistoryRecorder(storeURL: nil, legacyFileURL: nil))
                    model.settings.historyRetention = .year
                    UserDefaults.standard.set(state.days, forKey: "vitalsPeriodDays")
                    UserDefaults.standard.set(state.compares, forKey: "vitalsCompares")
                    UserDefaults.standard.set(state.filter.rawValue, forKey: "vitalsFilter")
                    model.history.preview(vitals: state.name.hasPrefix("fresh") ? freshVitals() : PretendHistory.makeVitals())
                    model.battery.preview(
                        BatterySnapshot(percentage: 81, powerSource: .powerAdapter, chargeState: .charging, timeRemaining: 35 * 60),
                        health: BatteryHealth(condition: .normal, maximumCapacity: 0.94, cycleCount: 296),
                        readings: BatteryReadings(temperature: 34.2, voltage: 12.71, current: 2.35))
                    let view = VitalsPane(model: model, page: state.page, throughTheDay: state.throughTheDay)
                        .formStyle(.grouped)
                        // "narrow" is the pane with the sidebar dragged as wide as it goes.
                        .frame(width: state.name.hasPrefix("narrow") ? 450 : 530, height: state.page == nil ? 760 : 1000)
                        .environment(\.colorScheme, scheme)
                    saveInWindow(
                        view, scheme: scheme, scrolledBy: 0,
                        to: folder.appending(path: "vitals-\(state.name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
            UserDefaults.standard.removeObject(forKey: "vitalsPeriodDays")
            UserDefaults.standard.removeObject(forKey: "vitalsCompares")
            UserDefaults.standard.removeObject(forKey: "vitalsFilter")
        }

        /// An hour of readings from a Mac on the charger, between 29.6 and 30.4 °C, and today's health.
        private static func freshVitals(now: Date = Date()) -> BatteryVitals {
            var vitals = BatteryVitals(retention: 366 * 24 * 3600, now: now)
            for (minutes, celsius) in [(55.0, 29.6), (40, 30.0), (25, 30.4), (10, 29.8)] {
                vitals.record(
                    VitalsReading(temperature: celsius, voltage: 12.68, batteryWatts: 0, systemWatts: 11, chargerWatts: 11, percentage: 88, isPluggedIn: true),
                    at: now.addingTimeInterval(-minutes * 60))
            }
            vitals.record(health: BatteryHealth(condition: .normal, maximumCapacity: 0.88, cycleCount: 569), at: now)
            return vitals
        }

        private static func renderOnboarding(to folder: URL) {
            for scheme in [ColorScheme.dark, .light] {
                for step in OnboardingView.Step.allCases {
                    let model = AppModel(settings: previewSettings(), history: HistoryRecorder(storeURL: nil, legacyFileURL: nil))
                    model.battery.preview(
                        BatterySnapshot(
                            percentage: 80, powerSource: .powerAdapter, chargeState: .notCharging, timeRemaining: nil, chargeTarget: 80,
                            targetReason: .chargeLimit))
                    let view = OnboardingView(model: model, startingAt: step, skipsOpening: true, finish: {}, close: {})
                        .environment(\.colorScheme, scheme)
                    saveInWindow(
                        view, scheme: scheme, scrolledBy: 0, to: folder.appending(path: "onboarding-\(step.rawValue)-\(scheme == .dark ? "dark" : "light").png")
                    )
                }
            }
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

        /// Draws `view` through AppKit in an offscreen window, which (unlike ImageRenderer) includes scroll views,
        /// scrolling the first one by `scrolledBy` points.
        private static func saveInWindow(_ view: some View, scheme: ColorScheme, scrolledBy offset: CGFloat, to url: URL) {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            if let scrollView = firstScrollView(in: hosting) {
                scrollView.contentView.scroll(to: CGPoint(x: 0, y: offset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            // A turn of the run loop, so SwiftUI hears about the scroll (and fades the top edge) before drawing.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }

        private static func firstScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView { return scrollView }
            return view.subviews.lazy.compactMap(firstScrollView(in:)).first
        }
    }
#endif
