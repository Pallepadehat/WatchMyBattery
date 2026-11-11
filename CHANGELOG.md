# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Lighter on your battery, and charging you can see.

### Added

- 🎯 **Where charging is headed.** While the Mac charges, the panel shows a bar from the charge so far to where macOS will stop, with light flowing towards it. When Optimized Battery Charging holds the battery at 80%, the bar marks 80% with a notch and hatches the part it's holding back, the time row says "Until 80%", and once it's there the panel says "Holding at 80%" instead of "Not Charging".
- ☕ **A way to support WatchMyBattery**: Settings › About has a Buy Me a Coffee button. The app stays free and open source either way.

### Changed

- ⚡ **A more graceful charging animation.** Charging to 80%, the glint in the menu bar rolls up to the target and settles there in a soft glow, rather than running on to the end of the battery. In the panel the wave eases in and out more softly and swells a little as it passes. Both now pause in Low Power Mode.
- 🪶 **Lighter on the Mac**, measured and checked before every release:
  - Recording a battery level, which happens every time it changes, takes about 0.1 µs instead of 140 µs.
  - Measuring apps with the panel open takes about half the time: processes WatchMyBattery isn't allowed to read (about a third of them) are skipped for 30 seconds instead of asked again every two.
  - With the panel open, it only redraws when a reading changes enough to show (2%), instead of every two seconds.
  - The charging animation skips frames nobody would see, and needs up to 60% fewer frames on a fuller battery at the same smoothness. Each frame's image is made once and reused.
  - Each app's colour is worked out once and shared, instead of once per list it appears in.
- The "Two batteries in your menu bar?" tip only shows while macOS's own battery is still in the menu bar.

### Fixed

- A warning in the history's saving code (a logger used across threads), which builds were meant to be free of.

## [0.2.1]

A tidier panel, and a chart that reads like iPhone's.

### Changed

- 📊 **The battery level chart is a bar every half hour**, like the one in iPhone's Battery settings, and taller, so it reads at a glance: green while plugged in, red when the battery ran low. Hours before the history began are left empty, so a new history no longer looks like one thin line stretched across the day.
- **The panel's details line up**: time left, battery health and Low Power Mode share one size and one row height, with the value on the right. "Fully Charged" and "Not Charging" now sit next to the power source, the way the system's Battery menu shows them, instead of on a row of their own.
- An app drawing almost no power on the adapter shows "<0.1 W" under its slice instead of "0.0 W".

## [0.2.0] - 2026-11-11

The last 24 hours of your battery.

### Added

- 📈 **Battery history in the panel**: a chart of the battery level over the last 24 hours, with the time plugged in marked, like the one in iPhone's Battery settings ([#28](https://github.com/Pallepadehat/WatchMyBattery/issues/28)). Fold it away with "Last 24 Hours" if you'd rather keep the panel short.
- **Time on battery since it was unplugged**, and the average drain per hour, for example "2:04 · 16% an hour" ([#29](https://github.com/Pallepadehat/WatchMyBattery/issues/29)).
- **The apps that used the most battery** over the last 24 hours, and how much battery time each one cost ([#27](https://github.com/Pallepadehat/WatchMyBattery/issues/27)).
- 🔥 **A notification for runaway apps**: when an app keeps using a lot of power on battery for a while (4 W or more over 15 minutes), with a button that quits it. Never for the app you're using. Turn it on in Settings › Notifications ([#30](https://github.com/Pallepadehat/WatchMyBattery/issues/30)).

### Changed

- For the history, apps are now measured in the background too, but only on battery, and only every five minutes: about a millisecond of CPU time each, roughly 12 ms an hour. On the adapter nothing changes. The history stays on your Mac, and Settings › Panel can turn it off or clear it ([#26](https://github.com/Pallepadehat/WatchMyBattery/issues/26)).

## [0.1.3] - 2026-11-11

A keyboard shortcut, Low Power Mode at your fingertips, and Shortcuts actions.

### Added

- ⌨️ **A keyboard shortcut for the panel.** Choose one in Settings › Menu Bar, and it opens and closes the panel from any app. If another app already has it, Settings says so ([#23](https://github.com/Pallepadehat/WatchMyBattery/issues/23)).
- 🍃 **Low Power Mode from the panel**: a switch under the battery health, and at 20% a suggestion to turn it on, which goes away until the next charge if you dismiss it. The low battery notification has a "Turn On Low Power Mode" button too. macOS has no way for apps to change it directly, so WatchMyBattery comes with a tiny helper that does only this: you allow it once in System Settings › Login Items (the first time you use the switch, or in Settings › General), and from then on the switch just works, with no password ([#24](https://github.com/Pallepadehat/WatchMyBattery/issues/24)).
- **Shortcuts actions**: Get Battery Level, Get Battery Time Left and Get App Using the Most Energy, for your own shortcuts and automations. They show up in Spotlight too, and Siri knows them ([#25](https://github.com/Pallepadehat/WatchMyBattery/issues/25)).

### Fixed

- Percentages in the low battery notification, VoiceOver and Shortcuts are written the way your language writes them ("12 %" in Danish).

## [0.1.2] - 2026-11-11

Health, notifications, Danish, and a battery that glows while it charges.

### Added

- ⚡ **A charging animation.** While the Mac charges, a soft swell of light flows into the menu bar battery and gives its terminal a little flash, and in the panel a gentle glow rolls across the big battery and lights up the bolt as it passes. It pauses while the displays sleep, follows Reduce Motion and Low Power Mode, and can be turned off in Settings › Menu Bar.
- **Battery health in the panel**: condition, maximum capacity and cycle count, the same numbers System Settings shows ([#11](https://github.com/Pallepadehat/WatchMyBattery/issues/11)).
- **Hidden apps.** Choose apps that never get a slice of the battery, so they can't be dragged out by accident: from a slice's menu ("Don't Show … in the Battery"), or in Settings › Panel ([#10](https://github.com/Pallepadehat/WatchMyBattery/issues/10)).
- **A low battery notification** at the levels you choose (20% and 10% to start with), naming the app using the most energy and how much time quitting it would give you, with a button that quits it ([#12](https://github.com/Pallepadehat/WatchMyBattery/issues/12)).
- **Keyboard and VoiceOver for the slices.** Tab moves between them (and the arrow keys along them), the time row previews quitting the selected app, and Delete quits it after asking. VoiceOver reads each one as, for example, "Figma, costs 48 minutes" ([#13](https://github.com/Pallepadehat/WatchMyBattery/issues/13)).
- 🇩🇰 **Danish**, and a language setting in Settings › General ([#14](https://github.com/Pallepadehat/WatchMyBattery/issues/14)).
- An About pane, with links to the source code, the changelog and the bug report form.

### Changed

- **Settings is laid out like System Settings**, with a sidebar of short panes: General, Menu Bar, Panel, Notifications, Updates and About.
- **When an app won't quit**, its slice comes back straight away and the panel says so ("Pages didn't quit: it may be asking what to do with unsaved changes"), with a button that brings the app forward. Before, the slice quietly came back a few seconds later ([#9](https://github.com/Pallepadehat/WatchMyBattery/issues/9)).
- The percentage and the bolt inside the menu bar battery are cut out of the charge and solid over the empty part, so they read clearly at any level, like the iPhone's battery.
- "Check for Updates…" in the menu bar icon's menu opens Settings › Updates and shows the result there.
- CI builds the app on the macOS 26 runner, and the panel's estimates are tested ([#15](https://github.com/Pallepadehat/WatchMyBattery/issues/15)).

### Fixed

- Clicking "Check Now" in Settings could freeze the Settings window. Sparkle's "You're up to date" message is an app-modal alert, and in a menu bar app it could open hidden behind the window. The check now runs without Sparkle's windows and shows its answer in Settings.
- Coloured icons in Settings' menu bar samples were drawn for a light menu bar even over a dark wallpaper.

## [0.1.1] - 2026-11-10

The first public release.

### Changed

- A new, simpler app icon: the menu bar battery, full, with "100" cut out of it. It follows macOS's light, dark and tinted icon styles.
- The panel's battery follows the menu bar icon's style, and the panel, its hover states and Settings look right in both light and dark mode.
- Settings is laid out like System Settings, with previews of each percentage style on the default macOS wallpaper.

### Fixed

- Dragging an app out of the panel to quit it could get stuck, leaving its icon on screen without quitting the app ([#7](https://github.com/Pallepadehat/WatchMyBattery/issues/7)).
- The panel opened too small or clipped, with square corners around the glass.

## [0.1.0] - 2026-11-10

The first release.

### Added

- 🔋 **A battery icon for the menu bar** that drains as your battery does, like the built-in one. Show the percentage inside the battery, next to it, or not at all. A bolt while charging, a plug while plugged in but not charging. Optionally red when low and green when charging, or monochrome to match the rest of the menu bar.
- **A Battery panel** that looks like the system's own: the percentage, the power source, time remaining, and a big capsule-shaped battery. The white fill is the charge you have left.
- **See what's draining it.** Coloured slices at the end of the fill are the apps using the most energy right now, each with its icon and an estimate of the battery time it costs (for example "−48m"). Helper processes count toward their app, the way Activity Monitor groups them.
- **Drag an app out to quit it.** Pull a slice out of the panel and the app quits with a poof, like removing an icon from the Dock. While you hover or drag a slice, "Time left" previews the time you'd gain (for example "4:50 +1:10").
- Settings for the percentage style, coloured states, what the centre of the battery shows (time or percentage), how many apps to show, asking before quitting, and launching at login.
- A button that opens the Control Center settings, so you can hide Apple's own battery icon.
- Automatic updates with Sparkle, from EdDSA-signed releases.
- One-command install, and build, packaging and release scripts.

[Unreleased]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Pallepadehat/WatchMyBattery/releases/tag/v0.1.0
