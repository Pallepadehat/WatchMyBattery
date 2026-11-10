# Security Policy

WatchMyBattery isn't sandboxed. It reads every running process's energy use (`proc_pid_rusage`), reads the battery's state from the IORegistry, and can quit other apps when you drag them out of its panel. It also updates itself with Sparkle, from EdDSA-signed releases on GitHub. If you find a way any of this could be abused, or any other security issue, please report it privately.

## Reporting a vulnerability

Please **don't** open a public issue. Instead, use [GitHub's private vulnerability reporting](../../security/advisories/new).

You'll get a response within a week. Fixes are released as soon as they're ready, and reporters are credited unless they'd rather not be.

Things that are especially interesting:

- Anything that could get a WatchMyBattery install to accept an update that wasn't signed with the project's Sparkle key.
- Anything that could make the app quit, signal or otherwise affect a process the user didn't choose.
- Anything that sends data off the Mac. WatchMyBattery makes no network requests other than Sparkle's update check.

## Supported versions

Only the latest release receives security fixes.
