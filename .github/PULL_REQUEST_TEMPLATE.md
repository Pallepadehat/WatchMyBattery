## What does this change?

<!-- A short description, and why it's needed. Link related issues: "Fixes #123". -->

<!-- Pull requests go into `develop`. Only `develop` is merged into `main`, for releases. -->

## How did you test it?

<!-- Screenshots or recordings are very welcome for anything visual. -->

## Checklist

- [ ] This pull request targets `develop`
- [ ] `swift test` passes in `Packages/BatteryKit`
- [ ] `swift format lint --strict -r WatchMyBattery WatchMyBatteryHelper Shared Packages/BatteryKit scripts` reports nothing
- [ ] The app builds without warnings
- [ ] The app is still idle with the panel closed (Activity Monitor, Release build)
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]` for anything users will notice
