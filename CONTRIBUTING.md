# Contributing to WatchMyBattery

Thanks for wanting to help! Bug fixes, polish, performance work, better estimates and new ideas are all welcome.

## Getting started

1. Fork and clone the repository.
2. Open `WatchMyBattery.xcodeproj` in Xcode 27 or later and press **⌘R**. (The app itself runs on macOS 14 and later.)
3. Run the logic tests:

   ```sh
   cd Packages/BatteryKit
   swift test
   ```

   Or everything at once, the way a release does: `./scripts/check.sh` (see [Testing](#testing)).

No Apple developer team is needed to build. See "Building" in the [README](README.md) if you want to sign with yours.

## Handy debug flags

Debug builds understand a few launch arguments (set them in the scheme, or pass them to the binary):

| Flag | What it does |
| --- | --- |
| `--show-panel` | Opens the panel right away (Release builds too) |
| `--show-settings` | Opens Settings; add `--settings-pane updates` (or `general`, `menuBar`, `panel`, `notifications`, `about`) for a pane |
| `--pretend-charging` | Shows the battery charging at 62%, to see the charging animation on a full battery (Release builds only with `--isolated`) |
| `--isolated <folder>` | Runs without touching the real app: fresh settings of its own, the history in `<folder>`, no updater, no keyboard shortcut. Works in Release builds, for the end-to-end checks. Its panel says "Test copy" |
| `--start-updater` | Turns on Sparkle, which debug builds leave off; add `--check-now` to press Check Now in Settings |
| `--render-previews <folder>` | Renders the panel and menu bar icons to PNG files and quits |
| `-AppleLanguages '(da)'` | Runs in Danish |

## The Low Power Mode helper

macOS has no API for changing Low Power Mode, so `WatchMyBatteryHelper` (a tiny launchd daemon, in `WatchMyBatteryHelper/`) runs `pmset` as root. The app registers it with `SMAppService` the first time you use the switch, and you allow it once in System Settings › Login Items. `Shared/` holds the XPC protocol both sides use. The helper only accepts the app signed by the same team as itself, so ad hoc builds can't use it; they ask for an administrator's password instead. To test it, run a build signed with your team (`./scripts/build.sh` with `Config/Local.xcconfig` set up) from `/Applications`. `sudo launchctl print system/com.pallepadehat.WatchMyBattery.helper` shows its state.

## Testing

There are four kinds of tests, and `./scripts/check.sh` runs them all (plus the linter and a warning-free build), the way `release.sh` does before every release:

| | Where | What it checks |
| --- | --- | --- |
| **Unit** | `Packages/BatteryKit/Tests/BatteryKitTests` | The logic, with made-up data: estimates, history, the charging glint's frames, icon colours. Includes equivalence tests that hold the optimized history and smoother against the simple versions they replaced, on many random days. |
| **Integration** | `Packages/BatteryKit/Tests/BatteryKitIntegrationTests` | Against this Mac: the battery reading agrees with `pmset`, the sampler credits work to the right app, the history survives the disk. Tests that need a battery skip themselves without one. |
| **Performance** | `Packages/BatteryKit/Sources/BatteryKitBenchmarks` | Times the hot paths (`swift run -c release BatteryKitBenchmarks`) against a budget each, from how often the app does it, and against `Packages/BatteryKit/Benchmarks/baseline.json`. |
| **End to end** | `scripts/e2e.swift` | Launches the real Release app, isolated, and checks it starts, records its history, and quits cleanly; renders the previews with the Debug build; and measures the app's own CPU time, wake-ups, energy and memory (the counters Activity Monitor reads) idle, charging, and with the panel open, against budgets and `scripts/e2e-baseline.json`. |

While the end-to-end check runs, a second battery (the test copy) appears in the menu bar. Leave it alone: one scenario needs its panel to stay open.

### Keeping it fast

- **Budgets** hold on any Mac. A benchmark or scenario over its budget fails the check: that's a real regression, or a much slower Mac.
- **Baselines** catch smaller slips: more than its tolerance slower than the recorded numbers fails, but only on the Mac that recorded them (the one releases are made on). Elsewhere the comparison is printed and nothing more.
- Made something faster? Record it, so it stays that way: `./scripts/check.sh --update-baselines`, and commit the two baseline files. Do the same after a change that's meant to cost more, and say why in the pull request.
- Each end-to-end scenario runs a few times and counts the fastest run: whatever else the Mac is doing only ever adds. Even so, quit busy apps first for steady numbers.
- `--quick` gives a quicker look; `--report-only` prints without failing on numbers; `--skip-e2e` leaves out the end-to-end check.

## Translations

Strings live in `WatchMyBattery/Localizable.xcstrings`. Xcode adds new strings to it when you build, and you translate them in its editor. Danish is the only translation so far; adding a language is very welcome (add it to the project's localizations, then translate in the catalog).

## Branches

| Branch | What it's for |
| --- | --- |
| `develop` | The default branch. All work lands here, through pull requests. |
| `main` | Production. It only ever gets merges from `develop`, and every release is made from it. |
| `feature/…` | New features, for example `feature/time-to-full`. |
| `fix/…` | Bug fixes, for example `fix/slice-drag-on-second-display`. |
| `chore/…` | Everything else: tooling, CI, docs, dependency bumps. |

Both `develop` and `main` are protected: changes go through a pull request, and CI (**Lint**, **BatteryKit tests** and **Build app**) has to pass.

So the usual flow is:

```sh
git switch develop
git pull
git switch -c fix/whatever-you-are-fixing
# …work, commit…
git push -u origin fix/whatever-you-are-fixing
```

Then open a pull request **into `develop`**.

## Before you open a pull request

- `./scripts/check.sh` passes (or at least `swift test` in `Packages/BatteryKit`, and `./scripts/check.sh --skip-e2e`).
- `swift format lint --strict -r WatchMyBattery WatchMyBatteryHelper Shared Packages/BatteryKit scripts` reports nothing. Run `swift format -i -r WatchMyBattery WatchMyBatteryHelper Shared Packages/BatteryKit scripts` to fix formatting automatically.
- The app builds without warnings.
- WatchMyBattery should stay idle while its panel is closed. If you touch the menu bar icon, notifications or sampling, the end-to-end check measures it; Activity Monitor's **Energy Impact** with a **Release** build is still a good second look.
- For visual changes, include a screenshot or a short recording.

For bigger changes, open an issue first so we can agree on the approach.

## Code style

- Swift 6 language mode. The app target defaults to main-actor isolation.
- Keep logic in `BatteryKit`: plain value types, no AppKit or SwiftUI, with unit tests. Anything you can test without a real battery belongs there.
- Name things for what they are, and add a doc comment explaining *why* whenever the code alone doesn't make it obvious.
- No polling. React to IOPowerSources notifications. Processes are sampled every two seconds while the panel is open, and for the history every five minutes on battery only (`HistoryRecorder`); don't add more sampling than that.
- Be honest about estimates in the UI: round sensibly and don't show more precision than the numbers have.

## Making a release

Releases are made by the maintainer from a Mac with the signing certificate, **from `main`**:

1. On `develop`, bump `MARKETING_VERSION` in the Xcode project (Target › General › Version).
2. Move the `[Unreleased]` entries in `CHANGELOG.md` into a new `## [x.y.z] - date` section, add its link at the bottom, and merge to `develop` through a pull request.
3. Open a pull request from `develop` into `main` and merge it.
4. Check out `main`, pull, and run `./scripts/release.sh`. It refuses to run on any other branch. It runs `./scripts/check.sh` first and stops if anything fails or got slower. Then it builds the app, packs it into `WatchMyBattery.dmg`, has Apple notarize it, makes the signed `appcast.xml`, tags the commit `vx.y.z` and publishes a GitHub release with both files attached. The app and `install.sh` always pick up the newest release.

To only make the disk image, run `./scripts/make-dmg.sh` (add `--notarize` for a notarized one).

### One-time setup: notarizing

Notarizing needs a **Developer ID Application** certificate in your keychain, your team ID in `Config/Local.xcconfig` (copy `Config/Local.xcconfig.example`), and a saved notarytool login:

```sh
xcrun notarytool store-credentials watchmybattery-notary \
  --apple-id <your Apple ID> --team-id <your team ID>
```

It asks for an [app-specific password](https://account.apple.com) and keeps it in your keychain. To use a different profile name, set `WATCHMYBATTERY_NOTARY_PROFILE`.

Without a Developer ID certificate, run `./scripts/release.sh --without-notarizing`. It signs with the best certificate you have, and `install.sh` still opens the app without a warning, but people downloading the .dmg in a browser will see Gatekeeper's warning.

### One-time setup: the Sparkle key

Each release carries `appcast.xml`, which is how the app finds updates ([Sparkle](https://sparkle-project.org)). It's signed with an EdDSA key called `WatchMyBattery` that lives in the maintainer's login keychain; its public half is `SUPublicEDKey` in `Config/Info.plist`. Sparkle's tools come with the Swift package, so build once (`./scripts/build.sh`) to fetch them, then:

```sh
# Make the key (once, ever). It prints the public key: put it in SUPublicEDKey in Config/Info.plist.
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account WatchMyBattery

# Print the public key again later.
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account WatchMyBattery -p

# Back up the private key, then store the file somewhere safe (a password manager) and delete it.
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account WatchMyBattery -x watchmybattery-sparkle-key.txt

# Restore it on a new Mac.
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account WatchMyBattery -f watchmybattery-sparkle-key.txt
```

**Back the key up.** Without it, copies already out there can't update: they only accept updates signed with that key. Never commit it (`.gitignore` ignores `*sparkle-key*.txt` as a safety net). Keep signing releases with the same Developer ID certificate too, since Sparkle also checks that an update comes from the same developer.

## Reporting bugs

Use the [bug report form](../../issues/new?template=bug_report.yml). Your macOS version and Mac model help a lot, and for estimate bugs, a screenshot of the panel next to Activity Monitor's Energy tab is gold.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By taking part, you agree to uphold it.
