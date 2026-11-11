#!/bin/zsh
# Everything that has to hold before a release, in one go. release.sh runs it first; run it yourself any time.
#
#   1. Lint           swift format, strict
#   2. Tests          BatteryKit's unit tests (made-up data) and integration tests (this Mac's battery, kernel, disk)
#   3. Benchmarks     BatteryKit's hot paths against their budgets and Packages/BatteryKit/Benchmarks/baseline.json
#   4. Build          the app, Release and Debug, without warnings
#   5. End to end     the real app, launched isolated: it works, and what it costs idle, charging and with the panel
#                     open, against budgets and scripts/e2e-baseline.json
#
#   ./scripts/check.sh                    everything
#   ./scripts/check.sh --quick            shorter benchmarks and measurements, for a quick look
#   ./scripts/check.sh --report-only      print the numbers, but don't fail on them (checks of behaviour still fail)
#   ./scripts/check.sh --skip-e2e         steps 1–4 only, for when you can't have a second battery in the menu bar
#   ./scripts/check.sh --update-baselines record this Mac's numbers as the new baselines, after a change that's
#                                         meant to make something slower (or once it's made faster, to keep it so)
#
# The baselines hold on the Mac that recorded them (the one releases are made on). Elsewhere only the budgets apply.
set -uo pipefail
cd "$(dirname "$0")/.."

QUICK=() REPORT=() UPDATE=() SKIP_E2E=0
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=(--quick) ;;
    --report-only) REPORT=(--report-only) ;;
    --update-baselines) UPDATE=(--update-baseline) ;;
    --skip-e2e) SKIP_E2E=1 ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

# `swift test` and xcodebuild need Xcode, not just the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" != *Xcode*.app* ]]; then
  XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1)
  [[ -n "$XCODE" ]] || { echo "This needs Xcode (27 or later)."; exit 1; }
  export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi

mkdir -p build/check
RESULTS=()
FAILED=0
step() {  # step <name> <command…>: runs it, keeps its output in build/check, and notes how it went
  local name=$1; shift
  local log="build/check/${name// /-}.log"
  print -P "\n%B▶ $name%b"
  local started=$SECONDS
  "$@" 2>&1 | tee "$log"
  local code=${pipestatus[1]}
  local took=$(( SECONDS - started ))
  if (( code == 0 )); then
    RESULTS+=("✅ $name (${took}s)")
  else
    RESULTS+=("❌ $name (${took}s), see $log")
    FAILED=1
  fi
  return $code
}

lint() { swift format lint --strict -r WatchMyBattery WatchMyBatteryHelper Shared Packages/BatteryKit scripts; }
tests() { (cd Packages/BatteryKit && swift test); }
benchmarks() {
  (cd Packages/BatteryKit && swift build -c release --product BatteryKitBenchmarks -q &&
    .build/release/BatteryKitBenchmarks $QUICK $REPORT $UPDATE --json ../../build/check/benchmarks.json)
}
# Ad hoc signed and without the hardened runtime, so it runs on any Mac (Sparkle comes signed by its own team).
# That changes nothing about how fast it is.
build_app() {
  local configuration
  for configuration in Release Debug; do
    echo "Building $configuration…"
    xcodebuild build -project WatchMyBattery.xcodeproj -scheme WatchMyBattery -configuration $configuration \
      -derivedDataPath build/check/DerivedData -destination 'platform=macOS' \
      CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO \
      > "build/check/xcodebuild-$configuration.log" 2>&1 || {
      grep -E "error:" "build/check/xcodebuild-$configuration.log" | sort -u | head -20
      return 1
    }
    # Warnings in our own code fail the check, as CONTRIBUTING asks.
    if grep -E "warning: .*(WatchMyBattery|BatteryKit|Shared)/" "build/check/xcodebuild-$configuration.log" | grep -v Sparkle | sort -u | grep .; then
      echo "The $configuration build has warnings."
      return 1
    fi
  done
}
end_to_end() {
  local products=build/check/DerivedData/Build/Products
  swiftc -O scripts/e2e.swift -o build/check/e2e-check &&
    build/check/e2e-check --app $products/Release/WatchMyBattery.app --debug-app $products/Debug/WatchMyBattery.app \
      $QUICK $REPORT $UPDATE --json build/check/e2e.json
}

step "Lint" lint
step "Tests" tests
step "Benchmarks" benchmarks
step "Build" build_app && (( ! SKIP_E2E )) && step "End to end" end_to_end
(( SKIP_E2E )) && RESULTS+=("⏭  End to end (skipped)")

print -P "\n%BSummary%b"
for result in "${RESULTS[@]}"; do echo "  $result"; done
if (( FAILED )); then
  echo "\nSomething needs a look before this can be released."
  exit 1
fi
echo "\nAll good. Numbers are in build/check/benchmarks.json and build/check/e2e.json."
