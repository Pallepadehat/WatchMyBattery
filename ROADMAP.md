# Roadmap

What's planned next. Each item has an issue, where the details and discussion live; the [milestones](https://github.com/Pallepadehat/WatchMyBattery/milestones) show progress. Ideas welcome: [open an issue](https://github.com/Pallepadehat/WatchMyBattery/issues/new/choose).

## 0.1.1: the first public release ✅

Released. A new icon, a polished panel and Settings in light and dark mode, and a fix for drag to quit getting stuck ([#7](https://github.com/Pallepadehat/WatchMyBattery/issues/7)). See the [changelog](CHANGELOG.md).

## 0.1.2: health, notifications and Danish ✅

Released. See the [changelog](CHANGELOG.md).

**The panel**

- [x] A charging animation in the menu bar and the panel, which can be turned off
- [x] Exclude apps from the battery ([#10](https://github.com/Pallepadehat/WatchMyBattery/issues/10))
- [x] Battery health: condition, maximum capacity and cycle count ([#11](https://github.com/Pallepadehat/WatchMyBattery/issues/11))
- [x] Show when an app won't quit, and why ([#9](https://github.com/Pallepadehat/WatchMyBattery/issues/9))
- [x] Keyboard and VoiceOver for app slices ([#13](https://github.com/Pallepadehat/WatchMyBattery/issues/13))

**Around it**

- [x] Low battery notification ([#12](https://github.com/Pallepadehat/WatchMyBattery/issues/12))
- [x] Danish translation, and a language setting ([#14](https://github.com/Pallepadehat/WatchMyBattery/issues/14))
- [x] Settings laid out like System Settings, with a pane for each part
- [x] Fix "Check Now" freezing Settings
- [x] Build the app in CI, and test the panel's estimates ([#15](https://github.com/Pallepadehat/WatchMyBattery/issues/15))

## 0.1.3: reach

- [ ] A keyboard shortcut to open the panel
- [ ] Turn Low Power Mode on and off from the panel, and suggest it when the battery is low
- [ ] Shortcuts actions: battery level, time left, the hungriest app

## 0.2.0: history

- [ ] Sample apps in the background while on battery, rarely and cheaply, and keep the last 24 hours
- [ ] Energy history: which apps drained the battery over the last hours
- [ ] Alerts for runaway apps: a notification when an app has used a lot of power for a while, with a Quit button

## 0.3.0: beyond the Mac's own battery

- [ ] A widget for the desktop and Notification Center
- [ ] Battery levels of AirPods, Magic Mouse, Magic Keyboard and Magic Trackpad in the panel
- [ ] Power draw in watts, and the charger's wattage when plugged in
- [ ] Time until full while charging, and why charging is paused (for example Optimized Battery Charging)

## Waiting on a Developer ID

- [ ] Sign with Developer ID and notarize releases, so new users don't have to click "Open Anyway" ([#8](https://github.com/Pallepadehat/WatchMyBattery/issues/8)). This needs a paid Apple Developer Program membership; until then, releases are signed without notarization and `install.sh` handles the first launch.
