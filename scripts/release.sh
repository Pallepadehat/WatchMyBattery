#!/bin/zsh
# Makes a release: builds WatchMyBattery.dmg and publishes it as a GitHub release, along with appcast.xml, where the
# app itself finds it (Sparkle) and install.sh does too. The version comes from MARKETING_VERSION in the Xcode project;
# the notes from its section in CHANGELOG.md.
#
# Releases are made from `main` only, which gets nothing but merges from `develop` (see CONTRIBUTING.md, "Making a
# release"). The script refuses to run on any other branch, or when main isn't in step with origin/main.
#
# The appcast is signed with the "WatchMyBattery" Sparkle key in your keychain (its public half is SUPublicEDKey in
# Config/Info.plist). Back it up: `generate_keys --account WatchMyBattery -x watchmybattery-sparkle-key.txt`. Without
# it, copies already out there can't update.
#
#   ./scripts/release.sh                       signed with Developer ID and notarized by Apple
#   ./scripts/release.sh --without-notarizing  signed with Developer ID if you have it (otherwise your Apple
#                                              Development certificate), not notarized. install.sh still opens it
#                                              without a warning.
#   ./scripts/release.sh --skip-checks         without running scripts/check.sh first (tests, benchmarks, end to end).
#                                              Only for when you've just run it on this very commit.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Pallepadehat/WatchMyBattery"
NOTARIZE=1
CHECKS=1
for arg in "$@"; do
  case "$arg" in
    --without-notarizing) NOTARIZE=0 ;;
    --skip-checks) CHECKS=0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

command -v gh >/dev/null || { echo "This needs the GitHub CLI: brew install gh, then gh auth login."; exit 1; }

# Only main is released. Everything else lands on develop first and reaches main through a pull request.
BRANCH=$(git symbolic-ref --quiet --short HEAD || echo "(detached HEAD)")
if [[ "$BRANCH" != "main" ]]; then
  echo "Releases are made from main, but you're on $BRANCH."
  echo "Merge develop into main through a pull request first, then:"
  echo "  git switch main && git pull && ./scripts/release.sh"
  exit 1
fi

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first, so the release matches the code."; exit 1; }
git fetch origin main --tags --quiet
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Your main isn't the same as origin/main. Run git pull (and push nothing to main directly), then try again."
  exit 1
fi

VERSION=$(xcodebuild -project WatchMyBattery.xcodeproj -scheme WatchMyBattery -showBuildSettings 2>/dev/null \
  | sed -nE 's/^[[:space:]]*MARKETING_VERSION = (.*)$/\1/p' | head -1)
[[ -n "$VERSION" ]] || { echo "Couldn't read MARKETING_VERSION from the project."; exit 1; }
TAG="v$VERSION"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already exists. Bump MARKETING_VERSION in the project (on develop) first."
  exit 1
fi

# This version's section of CHANGELOG.md becomes the release notes.
# It ends at the next version's heading or at the link references at the bottom.
NOTES=$(awk -v version="$VERSION" '
  /^## / { if (found) exit; if (index($0, "[" version "]")) { found = 1; next } }
  /^\[[^]]+\]: / { if (found) exit }
  found { print }
' CHANGELOG.md)
[[ -n "$NOTES" ]] || { echo "Add a \"## [$VERSION]\" section to CHANGELOG.md (on develop) first."; exit 1; }

# Nothing goes out that fails its tests, got slower than its budgets or baselines, or stopped working end to end.
if (( CHECKS )); then
  ./scripts/check.sh || { echo "scripts/check.sh found problems, so $TAG wasn't released."; exit 1; }
fi

if (( NOTARIZE )); then
  ./scripts/make-dmg.sh --notarize
else
  if [[ "$(security find-identity -v -p codesigning)" == *'"Developer ID Application'* ]]; then
    ./scripts/make-dmg.sh --sign
  else
    ./scripts/make-dmg.sh
  fi
  NOTES+=$'\n\n'"> This build isn't notarized by Apple. Install it with the one-liner below, which handles that. If you download the .dmg yourself, see the README for opening it the first time."
fi

# The appcast: one entry for this version, signed with our EdDSA key, pointing at this release's disk image. The app's
# SUFeedURL points at releases/latest/download/appcast.xml, so the newest release's appcast is always the one read.
GENERATE_APPCAST=$(find build/DerivedData/SourcePackages/artifacts -name generate_appcast -type f -perm -u+x | head -1)
[[ -n "$GENERATE_APPCAST" ]] || { echo "Couldn't find Sparkle's generate_appcast. Build once so Swift packages are fetched."; exit 1; }
rm -rf build/appcast
mkdir -p build/appcast
cp build/WatchMyBattery.dmg build/appcast/
"$GENERATE_APPCAST" --account WatchMyBattery \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$REPO/releases/tag/$TAG" --maximum-versions 1 build/appcast
[[ -f build/appcast/appcast.xml ]] || { echo "No appcast was made."; exit 1; }

NOTES+=$'\n\n'"### Install"$'\n\n```sh\ncurl -fsSL https://raw.githubusercontent.com/'"$REPO"$'/main/install.sh | bash\n```'

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" build/WatchMyBattery.dmg build/appcast/appcast.xml --repo "$REPO" --target main \
  --title "WatchMyBattery $VERSION" --notes "$NOTES"
echo "Released $TAG. Anyone can now install it with:"
echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
