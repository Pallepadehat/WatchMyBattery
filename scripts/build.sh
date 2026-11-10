#!/bin/zsh
# Builds WatchMyBattery.app into build/ with xcodebuild.
#
# Signing, best first:
#   WATCHMYBATTERY_SIGN=developer-id   your Developer ID Application certificate with a secure timestamp: what
#                                      notarization (and so a proper release) needs
#   (default)                          your Apple Development certificate, when Config/Local.xcconfig sets your team,
#                                      so macOS keeps recognising the app across builds and updates (its login item,
#                                      for one); otherwise ad hoc, which runs on this Mac only
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITIES=$(security find-identity -v -p codesigning)  # a variable, not `| grep -q`, which can trip pipefail
TEAM=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' Config/Local.xcconfig 2>/dev/null | head -1)

SIGNING=()
if [[ "${WATCHMYBATTERY_SIGN:-}" == "developer-id" ]]; then
  [[ "$IDENTITIES" == *'"Developer ID Application'* ]] || { echo "No Developer ID Application certificate in your keychain."; exit 1; }
  [[ -n "$TEAM" ]] || { echo "Set DEVELOPMENT_TEAM in Config/Local.xcconfig first."; exit 1; }
  # No get-task-allow entitlement: Apple refuses to notarize apps that have it.
  SIGNING=(CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM"
    OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
elif [[ -z "$TEAM" || "$IDENTITIES" != *'"Apple Development'* ]]; then
  echo "No team in Config/Local.xcconfig or no Apple Development certificate: signing ad hoc."
  SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

APP="build/DerivedData/Build/Products/Release/WatchMyBattery.app"
# A failed build must never leave an older app behind to be picked up below.
rm -rf "$APP"
mkdir -p build
# The build number counts commits, so every release has a higher one. Sparkle compares it to decide what's newer.
if ! xcodebuild -project WatchMyBattery.xcodeproj -scheme WatchMyBattery -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' \
  CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
  "${SIGNING[@]}" build > build/xcodebuild.log 2>&1; then
  grep -E "error:" build/xcodebuild.log | sort -u | head -20
  echo "Build failed. The whole log is in build/xcodebuild.log"
  exit 1
fi
grep -E "warning: .*(WatchMyBattery|BatteryKit)/" build/xcodebuild.log | sort -u || true
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

# Sparkle's helpers (the installer, the updater app) come signed ad hoc, and Xcode only re-signs the framework around
# them. Notarization, and Sparkle's own check of an update, need every piece signed by us.
if [[ "${WATCHMYBATTERY_SIGN:-}" == "developer-id" ]]; then
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  sign() { codesign --force --sign "Developer ID Application" --options runtime --timestamp "$@"; }
  sign "$SPARKLE/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
  sign "$SPARKLE/Autoupdate"
  sign "$SPARKLE/Updater.app"
  sign "$APP/Contents/Frameworks/Sparkle.framework"
  # And the app again, as its signature covers the framework.
  sign --preserve-metadata=entitlements,requirements,flags "$APP"
  codesign --verify --deep --strict "$APP" || { echo "The app's signature doesn't check out."; exit 1; }
fi

rm -rf build/WatchMyBattery.app
ditto "$APP" build/WatchMyBattery.app
echo "Built build/WatchMyBattery.app"
echo "Run it with: open build/WatchMyBattery.app"
