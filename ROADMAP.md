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

## 0.1.3: reach

**The panel**

- [x] Turn Low Power Mode on and off from the panel, and suggest it when the battery is low ([#24](https://github.com/Pallepadehat/WatchMyBattery/issues/24))

**The menu bar**

- [x] A keyboard shortcut to open the panel ([#23](https://github.com/Pallepadehat/WatchMyBattery/issues/23))

**Around it**

- [x] Shortcuts actions: battery level, time left, the hungriest app ([#25](https://github.com/Pallepadehat/WatchMyBattery/issues/25))

## 0.2.0: history

**Behind the scenes**

- [ ] Sample apps in the background while on battery, rarely and cheaply, and keep the last 24 hours ([#26](https://github.com/Pallepadehat/WatchMyBattery/issues/26))

**In the panel**

- [ ] Energy history: which apps drained the battery over the last hours ([#27](https://github.com/Pallepadehat/WatchMyBattery/issues/27))
- [ ] A battery level chart for the last 24 hours, with charging periods marked ([#28](https://github.com/Pallepadehat/WatchMyBattery/issues/28))
- [ ] Time on battery since last charged, and the average drain per hour ([#29](https://github.com/Pallepadehat/WatchMyBattery/issues/29))

**Around it**

- [ ] Alerts for runaway apps: a notification when an app has used a lot of power for a while, with a Quit button ([#30](https://github.com/Pallepadehat/WatchMyBattery/issues/30))

## 0.3.0: accessories

**The AirPods card** ([#31](https://github.com/Pallepadehat/WatchMyBattery/issues/31))

- [ ] When AirPods or other Bluetooth headphones connect, a card slides in below the menu bar showing the battery of each earbud and the case, like on iPhone
- [ ] A ring for each battery, filling up as the card appears, and the case's charging state
- [ ] Choose where the card appears, how long it stays, or turn it off

**In the panel**

- [ ] Battery levels of AirPods, Magic Mouse, Magic Keyboard and Magic Trackpad ([#32](https://github.com/Pallepadehat/WatchMyBattery/issues/32))
- [ ] Low battery notifications for accessories, with their own threshold ([#33](https://github.com/Pallepadehat/WatchMyBattery/issues/33))

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
