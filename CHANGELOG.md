# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Pallepadehat/WatchMyBattery/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Pallepadehat/WatchMyBattery/releases/tag/v0.1.0
