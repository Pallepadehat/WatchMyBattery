# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.2] - 2026-11-13

Less in the battery when you want less, and a Settings window that comes to the front.

### Added

- 🖥️ **Hide Display & System from the battery.** Right-click its slice and choose *Don't Show Display & System in the Battery*. Turn it back on in Settings › Panel.

### Fixed

- 🪟 **Check for Updates… comes to the front.** Chosen from the menu bar icon's right-click menu, Settings opened behind every other window. Now it opens on top, with focus.

## [0.3.1] - 2026-11-13

Your iPhone in the panel, tidied up, and a refresh button that does what it says.

### Changed

- 📱 **A cleaner row for your iPhone and iPad.** When its reading is old, the name has room to show in full, the level sits at the end of the line like every other accessory's, and under it, how old the reading is, with a **Refresh** button right beside it.
- The row keeps up while the panel is open: a reading that turns old says so, and how old it is, without closing and opening the panel.

### Fixed

- 🔄 **Refresh works.** Clicking it says *Reading…* while it reads, and when the iPhone is asleep or off your Wi‑Fi, the row says *Couldn't reach it* for a few seconds instead of doing nothing. It gives up after 12 seconds, and a reading that comes in later still shows.
- A read on a timer, or a device coming or going, could cut a refresh short and leave the button greyed out until the app restarted.

## [0.3.0] - 2026-11-13

Accessories, your iPhone, a charge limit, and what happens while your Mac sleeps.

### Added

- 🎧 **The AirPods card.** When AirPods or other headphones connect, a glass card slides in below the menu bar with a ring for each earbud and the case, filling up as it appears, like on iPhone ([#31](https://github.com/Pallepadehat/WatchMyBattery/issues/31)). When both earbuds are about the same, they share one ring. A bolt shows what's charging, and the levels keep up if they arrive a moment after the earbuds connect. It never takes focus from the app you're in, stays while the pointer is over it, and opens the panel when clicked. VoiceOver reads it out. In Settings › Accessories, put it below the menu bar icon, top center or top right, keep it for 3 to 12 seconds, try it with Show Card, or turn it off.
- 🖱️ **Accessories in the panel**: each connected AirPods, Beats, Magic Mouse, Magic Keyboard, Magic Trackpad or game controller, with the level of every part ([#32](https://github.com/Pallepadehat/WatchMyBattery/issues/32)). It shows on Macs without a battery too.
- 🔔 **A notification when an accessory runs low**, at its own level: 10% to 30%, 20% to start with ([#33](https://github.com/Pallepadehat/WatchMyBattery/issues/33)). It goes by the lower earbud, never the case, and comes again only once the accessory has charged. Turn it on in Settings › Notifications.
- 🍏 **Every Apple accessory, by name and by look.** All AirPods (from the first ones to AirPods 4, AirPods Pro 3 and AirPods Max), the Beats line (Powerbeats, Powerbeats Pro, Fit Pro, Studio Buds and Studio Buds +, Solo Buds, Flex, Solo, Studio, Pill) and the Magic Mouse, Keyboard and Trackpad each get their own symbol, for each earbud and the case too. Renamed ones show their model under the name ("Gym", Powerbeats Pro 2).
- 📱 **Your iPhone and iPad** in the panel, next to your accessories: over the cable, or over Wi‑Fi once you've turned on *Show this iPhone when on Wi‑Fi* in Finder. Settings › Accessories walks you through it. An iPhone drops off Wi‑Fi whenever it locks, so its last reading stays for a day, saying how old it is, with a button to read it again.
- 🔋 **A charge limit.** Hold the battery at 80%, 85%, 90% or 95% while plugged in, so it lasts longer. It's macOS's own charge limit (Apple silicon, macOS 26.4 or later), so it holds when WatchMyBattery isn't running, and System Settings › Battery shows the same thing. Change it from the panel or with a slider in Settings › Charging. **Charge to Full Once** lifts it for a long day away from a charger, and it comes back when you unplug.
- 🔌 **When it's charged**: a notification when the battery reaches a level you choose (80% to 100%), for unplugging by hand. With a charge limit below that level, it comes at the limit.
- 🌙 **Sleep.** How much battery the last sleep used, right in the panel, and every recent sleep in Settings › Sleep, with how fast each one drained. A Mac asleep should use about 1% an hour: when a sleep used much more, an optional notification says so on waking.
- 👀 **What's keeping your Mac awake**: the app that's stopping it from sleeping right now, with its icon and what it's doing, like Music playing audio. It names the app behind macOS's own helpers (sound playing for a browser, say), and leaves out macOS's background processes.
- 🌡️ **Temperature, voltage and current** in the panel, from the battery's own controller, with a note when it's warm enough for macOS to slow charging.
- 🔍 **Click an app's slice** to see the processes behind it (a browser's helpers and renderers) and how much each uses, with Quit, and Force Quit for an app that's stopped responding.
- 🖥️ **Display & System**: a slice of its own for the power no app accounts for (the screen, graphics, Wi‑Fi, Bluetooth and macOS itself).
- 📤 **Export the history** as a spreadsheet (CSV) or JSON, and keep it for 2 weeks, 1 or 3 months, or a year.
- New Settings panes: Accessories, Charging and Sleep.

### Changed

- Settings › Charging is made of standard macOS controls: a stepped slider for the limit, like System Settings' own.
- Accessories are read from what macOS already knows, without Bluetooth permission: macOS announces connections and AirPods' levels, so nothing is polled for them. The Magic accessories' levels are read again every quarter of an hour, only while one is connected.

## [0.2.6] - 2026-11-12

Calendar access when you ask for it.

### Changed

- 📅 **You choose when to give calendar access.** WatchMyBattery no longer brings up macOS's calendar prompt by itself, when the app opens or when you turn on *Charge Before Meetings*. Under the switch in Settings › Notifications, a **Calendar Access** row has an **Allow…** button: click it and macOS asks, once. Once it's allowed, the row says so with a check. If access was turned off, **Open…** goes to System Settings › Privacy & Security › Calendars.
- Access changed in System Settings is noticed when you come back to Settings or open the panel, so the warning starts or stops without a restart.

## [0.2.5] - 2026-11-12

Insights: the battery, your day, and what's unusual ([#58](https://github.com/Pallepadehat/WatchMyBattery/issues/58)).

### Added

- 📅 **Charge before your meeting.** When the battery won't last through a meeting on your calendar, the panel and a notification say so in time: "Charge before your 14:00 meeting. The battery should last until about 13:30." Choose how far ahead in Settings › Notifications, from 15 minutes to 2 hours (30 to start with). It uses the Calendar app's calendars, asks for access only when you turn it on, and reads only when events start and end. All-day events, ones you've declined and ones marked as free don't count. Plug in and the notification goes away by itself.
- 📈 **More than usual.** When the Mac draws clearly more power than it usually does at this time of day, the panel says by how much, and which app is behind it: "About 30% more than at this time on most days, mostly because of Xcode." It waits until it knows what's usual (about a week), and says nothing rather than guess.
- ✨ **A new app using a lot.** An app that hadn't used much battery in the last two weeks and is now among the hungriest gets a line in the panel, once, with a button that quits it.
- 📊 **10 Days** in the panel's history, next to 24 Hours: how much battery each day used, an average day on battery, and the apps that used the most over the ten days. The panel remembers which one you looked at last.
- Each insight can also be a notification (Settings › Notifications › Insights), and the panel's insights can be turned off in Settings › Panel.

### Changed

- 🗄️ **The history is kept with SwiftData**, and now goes back two weeks, in hourly summaries: time on battery, battery used, the Mac's power draw, and each app's energy. Saving writes only what changed (about 1.5 ms for a sample) instead of rewriting the whole history. Your existing history moves over the first time 0.2.5 opens, and a damaged store starts over instead of stopping the app. It still never leaves your Mac.
- Clearing the history clears the two weeks and what's usual too.
- Danish for the charge bar's labels, which 0.2.2 left in English.

## [0.2.2] - 2026-11-11

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

## [0.2.1] - 2026-11-11

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

[Unreleased]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.6...v0.3.0
[0.2.6]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.2...v0.2.5
[0.2.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Pallepadehat/WatchMyBattery/releases/tag/v0.1.0
