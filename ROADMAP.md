# Roadmap

What's planned next. Each item has an issue, where the details and discussion live; the [milestones](https://github.com/Pallepadehat/WatchMyBattery/milestones) show progress. Ideas welcome: [open an issue](https://github.com/Pallepadehat/WatchMyBattery/issues/new/choose).

## 0.1.1: the first public release ✅

Released. A new icon, a polished panel and Settings in light and dark mode, and a fix for drag to quit getting stuck ([#7](https://github.com/Pallepadehat/WatchMyBattery/issues/7)). See the [changelog](CHANGELOG.md).

## 0.1.2: health, notifications and Danish ✅

Released. See the [changelog](CHANGELOG.md).

**The panel**

- [x] Exclude apps from the battery ([#10](https://github.com/Pallepadehat/WatchMyBattery/issues/10))
- [x] Battery health: condition, maximum capacity and cycle count ([#11](https://github.com/Pallepadehat/WatchMyBattery/issues/11))
- [x] Show when an app won't quit, and why ([#9](https://github.com/Pallepadehat/WatchMyBattery/issues/9))
- [x] Keyboard and VoiceOver for app slices ([#13](https://github.com/Pallepadehat/WatchMyBattery/issues/13))

**The menu bar**

- [x] A gentle charging animation in the menu bar and the panel ([#22](https://github.com/Pallepadehat/WatchMyBattery/issues/22))

**Around it**

- [x] Low battery notification ([#12](https://github.com/Pallepadehat/WatchMyBattery/issues/12))
- [x] Danish translation, and a language setting ([#14](https://github.com/Pallepadehat/WatchMyBattery/issues/14))
- [x] Settings laid out like System Settings, with a pane for each part
- [x] Build the app in CI ([#15](https://github.com/Pallepadehat/WatchMyBattery/issues/15))

## 0.1.3: reach ✅

Released. See the [changelog](CHANGELOG.md).

**The panel**

- [x] Turn Low Power Mode on and off from the panel, and suggest it when the battery is low ([#24](https://github.com/Pallepadehat/WatchMyBattery/issues/24))

**The menu bar**

- [x] A keyboard shortcut to open the panel ([#23](https://github.com/Pallepadehat/WatchMyBattery/issues/23))

**Around it**

- [x] Shortcuts actions: battery level, time left, the hungriest app ([#25](https://github.com/Pallepadehat/WatchMyBattery/issues/25))

## 0.2.0: history ✅

Released. See the [changelog](CHANGELOG.md).

**Behind the scenes**

- [x] Sample apps in the background while on battery, rarely and cheaply, and keep the last 24 hours ([#26](https://github.com/Pallepadehat/WatchMyBattery/issues/26))

**In the panel**

- [x] Energy history: which apps drained the battery over the last hours ([#27](https://github.com/Pallepadehat/WatchMyBattery/issues/27))
- [x] A battery level chart for the last 24 hours, with charging periods marked ([#28](https://github.com/Pallepadehat/WatchMyBattery/issues/28))
- [x] Time on battery since last charged, and the average drain per hour ([#29](https://github.com/Pallepadehat/WatchMyBattery/issues/29))

**Around it**

- [x] Alerts for runaway apps: a notification when an app has used a lot of power for a while, with a Quit button ([#30](https://github.com/Pallepadehat/WatchMyBattery/issues/30))

## 0.2.2: lighter, and charging you can see ✅

Released. See the [changelog](CHANGELOG.md).

**Behind the scenes**

- [x] Unit, integration, end to end and performance tests, run by `scripts/check.sh` before every release, with budgets and baselines so the app stays light
- [x] Faster history, app measuring and charging animation, and fewer redraws of the open panel

**In the panel**

- [x] Where charging is headed: a bar to the charge target, with Optimized Battery Charging's 80% marked
- [x] A more graceful charging animation, in the menu bar and the panel

## 0.2.5: insights ✅

Released. See the [changelog](CHANGELOG.md).

Things worth acting on, at the right moment, from what WatchMyBattery already measures ([#58](https://github.com/Pallepadehat/WatchMyBattery/issues/58)).

- [x] Charge before your meeting: "Charge before your 14:00 meeting. The battery should last until about 13:30." (opt in, the Calendar app, start and end times only, warning time set in Settings)
- [x] More than usual: "You're using 20% more power than you usually do at this time, mostly because of Xcode."
- [x] A new app using a lot of power: one that hasn't shown up in the last week or two and is now among the hungriest
- [x] Two weeks of history, kept small with SwiftData: an hourly summary of the drain, power and apps, rather than every sample
- [x] Ten days in the panel's history, like iPhone's Battery settings

## 0.2.6: calendar access when you ask ✅

Released. See the [changelog](CHANGELOG.md).

- [x] Ask for calendar access with a button in Settings, instead of macOS's prompt appearing when the app opens

## 0.3.0: accessories ✅

Released, with a charge limit, sleep, your iPhone and iPad, and more besides. See the [changelog](CHANGELOG.md).

**The AirPods card** ([#31](https://github.com/Pallepadehat/WatchMyBattery/issues/31))

- [x] When AirPods or other Bluetooth headphones connect, a card slides in below the menu bar showing the battery of each earbud and the case, like on iPhone
- [x] A ring for each battery, filling up as the card appears, and the case's charging state
- [x] Choose where the card appears, how long it stays, or turn it off

**In the panel**

- [x] Battery levels of AirPods, Magic Mouse, Magic Keyboard and Magic Trackpad ([#32](https://github.com/Pallepadehat/WatchMyBattery/issues/32))
- [x] Low battery notifications for accessories, with their own threshold ([#33](https://github.com/Pallepadehat/WatchMyBattery/issues/33))

## 0.3.1: your iPhone, tidied up ✅

Released. See the [changelog](CHANGELOG.md).

- [x] A cleaner iPhone and iPad row: the whole name, and how old the reading is beside its level
- [x] A refresh button that shows it's reading, and says when the iPhone couldn't be reached

## 0.3.2: less in the battery ✅

Released. See the [changelog](CHANGELOG.md).

- [x] Hide the Display & System slice from the battery, right from its menu
- [x] Settings, opened from the menu bar icon's menu, comes to the front

## 0.4.0: delight

**Charging**

- [ ] An optional chime when you plug in or unplug ([#34](https://github.com/Pallepadehat/WatchMyBattery/issues/34))
- [ ] Why charging is paused, for example by Optimized Battery Charging ([#35](https://github.com/Pallepadehat/WatchMyBattery/issues/35))
- [ ] The charger's wattage, and a hint when it's too weak to charge while you work ([#36](https://github.com/Pallepadehat/WatchMyBattery/issues/36))

**The menu bar**

- [ ] The Mac's total power draw in watts, as an extra label or its own menu bar style ([#37](https://github.com/Pallepadehat/WatchMyBattery/issues/37))
- [ ] More icon styles: a ring, the number alone, or time left instead of the percentage ([#38](https://github.com/Pallepadehat/WatchMyBattery/issues/38))

## 0.5.0: everywhere

**Widgets and Shortcuts**

- [ ] A widget for the desktop and Notification Center: the battery, time left and the hungriest apps ([#39](https://github.com/Pallepadehat/WatchMyBattery/issues/39))
- [ ] An accessories widget, with your AirPods and Magic devices ([#40](https://github.com/Pallepadehat/WatchMyBattery/issues/40))
- [ ] Shortcuts automations: run a shortcut when the battery drops below a level or the charger is connected ([#41](https://github.com/Pallepadehat/WatchMyBattery/issues/41))

**Battery care**

- [ ] Battery health over time: maximum capacity and cycle count, month by month ([#42](https://github.com/Pallepadehat/WatchMyBattery/issues/42))
- [ ] A weekly summary: battery time used, the apps that used the most, and how it compares with last week ([#43](https://github.com/Pallepadehat/WatchMyBattery/issues/43))
- [ ] Rules for low battery: turn on Low Power Mode or quit chosen apps at a level you pick ([#44](https://github.com/Pallepadehat/WatchMyBattery/issues/44))

## Waiting on a Developer ID

- [ ] Sign with Developer ID and notarize releases, so new users don't have to click "Open Anyway" ([#8](https://github.com/Pallepadehat/WatchMyBattery/issues/8)). This needs a paid Apple Developer Program membership; until then, releases aren't notarized and `install.sh` handles the first launch.
