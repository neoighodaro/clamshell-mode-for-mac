#!/bin/bash
# Builds a Developer ID signed, hardened Clam.app and prints its path (and only that) on stdout.
# Everything else goes to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Team ID: first argument, then $DEVELOPMENT_TEAM, then Config/Local.xcconfig, then a prompt.
TEAM="${1:-${DEVELOPMENT_TEAM:-}}"
if [ -z "$TEAM" ]; then
  TEAM="$(xcodebuild -project Clam.xcodeproj -scheme Clam -configuration Release \
    -showBuildSettings 2>/dev/null | awk '$1 == "DEVELOPMENT_TEAM" { print $3; exit }')"
fi
if [ -z "$TEAM" ] && [ -t 0 ]; then
  read -r -p "Team ID: " TEAM
fi
if [ -z "$TEAM" ]; then
  echo "build-release: no team ID; pass it as the first argument" >&2
  exit 1
fi
LOG="$ROOT/build/release/xcodebuild.log"
mkdir -p "$ROOT/build/release"

if ! xcodebuild -project Clam.xcodeproj -scheme Clam -configuration Release \
  -derivedDataPath build/release \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build >"$LOG" 2>&1; then
  echo "xcodebuild failed; last 40 lines of $LOG:" >&2
  tail -40 "$LOG" >&2
  exit 1
fi
tail -3 "$LOG" >&2

APP="$ROOT/build/release/Build/Products/Release/Clam.app"

fail() {
  echo "build-release: $1" >&2
  exit 1
}

# Requires one signing property of one binary; $1 name, $2 codesign output, $3 pattern, $4 description.
require() {
  if ! printf '%s\n' "$2" | grep -Eq "$3"; then
    fail "$1 is missing $4"
  fi
}

check_binary() {
  local name="$1" path="$2" info ents
  info="$(codesign -dvv "$path" 2>&1)" || fail "$name: codesign could not read the signature"
  require "$name" "$info" '^Authority=Developer ID Application:' "an 'Authority=Developer ID Application:' line"
  require "$name" "$info" "^TeamIdentifier=$TEAM\$" "TeamIdentifier=$TEAM"
  require "$name" "$info" '^CodeDirectory .*flags=0x[0-9a-f]+\(.*runtime.*\)' "the hardened runtime flag"
  require "$name" "$info" '^Timestamp=' "a secure Timestamp= line"
  ents="$(codesign -d --entitlements - "$path" 2>&1 || true)"
  if printf '%s\n' "$ents" | grep -Eq '<key>|\[Key\]'; then
    fail "$name carries entitlements (none are allowed, including get-task-allow)"
  fi
}

codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict failed for $APP"
check_binary "Clam.app" "$APP"
check_binary "ClamWatchdog" "$APP/Contents/MacOS/ClamWatchdog"
echo "$APP"
