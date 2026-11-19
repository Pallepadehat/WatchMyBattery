# Architecture

A map of WatchMyBattery for anyone reading or changing the code: how the pieces fit together, and where each feature lives. For building, testing and releasing, see [CONTRIBUTING](../.github/CONTRIBUTING.md).

## The big picture

```text
                 macOS (IOKit, the kernel's energy counters, pmset, Bluetooth, Calendar)
                                          │
                     ┌────────────────────┴────────────────────┐
                     │  Packages/BatteryKit                    │  plain Swift: reading and working things out,
                     │  readers · estimates · history · alerts │  tested without the app
                     └────────────────────┬────────────────────┘
                                          │
                     ┌────────────────────┴────────────────────┐
                     │  Monitors (Sources/WatchMyBattery)      │  @Observable, one per subject: the battery,
                     │  BatteryMonitor · AppUsageMonitor · …   │  apps, history, sleep, accessories…
                     └────────────────────┬────────────────────┘
                                          │  owned by
                                     ┌────┴─────┐
                                     │ AppModel │  the actions that span them, and when each one runs
                                     └────┬─────┘
             ┌───────────────┬────────────┼──────────────┬────────────────┐
         Menu bar icon     Panel     AirPods card      Settings      Notifications
```

- **BatteryKit** knows nothing about the app's interface. It reads the system (power sources, battery readings, process energy, accessories) and works things out from what it reads: time estimates, the charging glint's frames, insights, when to warn. Everything that can be tested is here, and it's where the unit, integration and benchmark targets live.
- **Monitors** in the app wrap BatteryKit for SwiftUI: each one is `@Observable`, holds the latest state of one thing, and decides how often to read it. They're as idle as possible: apps are measured only while the panel is open (and, for the history, every five minutes on battery), and what's listening to macOS's own announcements costs nothing in between.
- **`AppModel`** owns the monitors and the settings, starts them, and holds the actions that touch more than one, such as opening the panel or turning Low Power Mode on.
- **The interface** (the menu bar icon, the panel, the AirPods card and Settings) only reads the monitors and calls `AppModel`. It's a plain AppKit app with SwiftUI inside: everything hangs off an `NSStatusItem` and borderless panels, which need more control than `MenuBarExtra` gives.

## The app, folder by folder

Everything is in `Sources/WatchMyBattery`. The Xcode project uses synchronized folders, so a new file is picked up wherever you put it.

| Folder | What's in it |
| --- | --- |
| `App` | The entry point and app delegate (`WatchMyBatteryApp`), `AppModel`, `Updater` (Sparkle), and `UsageStats`, Count This Mac's opt-in daily ping to `Server/stats`. |
| `Battery` | The Mac's own battery: `BatteryMonitor` (level, state, health, readings and the charger), `ChargeLimit`, `LowPowerMode` (which switches it through the helper), `PowerDrawMonitor` for the menu bar's watts, and `ChargingChime`. |
| `Energy` | The apps using power: `AppUsageMonitor` measures them while the panel is open, quits the one you drag out, and notices when it doesn't quit. `IconTint` picks each app's colour from its icon. |
| `History` | `HistoryRecorder`: the battery level and the apps' energy over time, stored on disk, for the charts, "Used the most battery" and Settings › History; and the battery's vitals (temperature, voltage, power, health; `BatteryVitals`, kept in `VitalsStore`), read every five minutes, for Settings › Battery Health. |
| `Insights` | `InsightsMonitor` and the words it uses (`InsightText`): more drain than usual, a new app, and charging before a meeting (`CalendarWatcher`). |
| `Sleep` | `SleepMonitor`: how much each sleep used, and what's keeping the Mac awake. |
| `Notifications` | `LowBatteryNotifier`: every notification the app sends, and their buttons. |
| `Accessories` | AirPods, Magic accessories, iPhone and iPad: `AccessoryMonitor`, their rows in the panel, and the AirPods card that slides in when they connect. |
| `MenuBar` | The status item, `MenuBarItem` (the icon and text it shows, shared with Settings), the icon in its three styles (`BatteryIcon`, `BatteryIcon+Styles`) and its charging animation, the keyboard shortcut, and the panel's window (`BatteryPanelController`). |
| `Onboarding` | The welcome tour: its opening animation (`OnboardingIntro`), the steps (`OnboardingView`), and its window. Shown once, and from Settings › General. |
| `Panel` | What the panel shows: `BatteryPanelView` lays it out, with the gauge, the rows and the sections around it. `HistorySection` is the history at the bottom, and `AppHistoryViews` the pieces an app's history is drawn with there and in Settings. `DragToQuit` is pulling an app out of the battery to quit it. |
| `Settings` | `AppSettings` (every preference, in `UserDefaults`), the Settings window, and its panes. `HistoryPane` is Settings › History, with a page for each app; `VitalsPane` is Settings › Battery Health. |
| `Intents` | The Shortcuts actions. |
| `Support` | Small helpers used across the app: launch options, logging, the language setting, opening System Settings. |
| `Resources` | The asset catalog, the app icon (an Icon Composer icon, drawn by `scripts/generate-icon.swift`) and the string catalogs with their translations. |
| `Debug` | `PreviewRenderer`, which renders the panel, icons and cards to PNGs for checking the design: `WatchMyBattery --render-previews <folder>`, Debug builds only. |

## BatteryKit

`Packages/BatteryKit` is a Swift package with three targets:

- **`BatteryKit`**, the library. Roughly: *readers* that talk to the system (`PowerSourceReader`, `SystemPowerReader`, `BatteryReadings`, `PowerAdapter`, `ProcessEnergySampler`, `AccessoryReader`, `AppleDeviceReader`, `ChargeLimitClient`, `PowerAssertions`), *models* of what they read (`BatterySnapshot`, `BatteryHealth`, `Accessory`, `SleepLog`), and the *logic* on top (`Estimates`, `TimeEstimate`, `BatteryHistory` with `HistoryStore`, `UsageProfile` with `UsageReport` (the history over any stretch of time, and one app's), `Insights`, `RunawayDetector`, `LowBatteryAlert`, `ChargingGlint`, `ChargingNote`, `PowerChime`, `MenuBarReadout`, `GaugeLayout`).
- **`BatteryKitBenchmarks`**, which times the hot paths against a budget each and a recorded baseline.
- The tests: **`BatteryKitTests`** run on made-up data, and **`BatteryKitIntegrationTests`** against the Mac they run on.

## The helper

macOS has no API for apps to change Low Power Mode. `Sources/WatchMyBatteryHelper` is a tiny launchd daemon that does only that, by running `pmset` as root. The app registers it with `SMAppService` (you allow it once in System Settings › Login Items) and talks to it over XPC, using the protocol in `Sources/Shared`. The helper accepts connections only from WatchMyBattery itself, signed by the same team, takes nothing but on or off, and quits when it's idle.

## What's stored, and where

Everything stays on the Mac:

- **Preferences** in `UserDefaults`, through `AppSettings`.
- **History** in `~/Library/Application Support/WatchMyBattery/History.store`, kept as long as Settings says.
- **Sleeps** in `~/Library/Application Support/WatchMyBattery/Sleep.json`.

An isolated run (the end-to-end checks in `scripts/e2e.swift`) keeps all of these in a folder of its own, so it never touches yours.

## Where to start

- **Changing the panel:** `Panel/BatteryPanelView.swift`, then the section you're after. Render the previews before and after to compare.
- **A new reading or estimate:** add it to BatteryKit with a test, then show it through the monitor that owns that subject.
- **A new setting:** add it to `AppSettings`, then to its pane in `Settings`.
- **A new string:** write it in English in the code. Xcode adds it to `Resources/Localizable.xcstrings`, where it gets its Danish translation.
