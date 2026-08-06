#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DERIVED_DATA=${DERIVED_DATA_PATH:-/private/tmp/DiafitReleaseAuditDerived}

fail() {
  printf '%s\n' "release check failed: $1" >&2
  exit 1
}

printf '%s\n' 'Diafit release audit'

command -v plutil >/dev/null 2>&1 || fail 'plutil is required'
command -v xcodebuild >/dev/null 2>&1 || fail 'xcodebuild is required'
command -v node >/dev/null 2>&1 || fail 'Node.js is required'

plutil -lint "$ROOT/Diafit/Supporting/PrivacyInfo.xcprivacy" >/dev/null
plutil -lint "$ROOT/Diafit/Supporting/Info-Release.plist" >/dev/null
plutil -lint "$ROOT/Diafit/Diafit.entitlements" >/dev/null

grep -q 'PrivacyInfo.xcprivacy' "$ROOT/Diafit.xcodeproj/project.pbxproj" || fail 'privacy manifest is not in the Xcode target'
grep -q 'INFOPLIST_FILE = Diafit/Supporting/Info-Release.plist' "$ROOT/Diafit.xcodeproj/project.pbxproj" || fail 'Release target is not using the release plist'

if grep 'A00800000000000000000004 /\* Release \*/' "$ROOT/Diafit.xcodeproj/project.pbxproj" | grep -q 'INFOPLIST_KEY_NSLocalNetworkUsageDescription'; then
  fail 'Release configuration contains the Debug local-network usage description'
fi

if git -C "$ROOT" grep -nE 'sk-[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{20,}' -- ':!Backend/.env.example' ':!*.md' >/dev/null 2>&1; then
  fail 'a provider-looking secret is tracked in source'
fi

npm --prefix "$ROOT/Backend" run check >/dev/null
npm --prefix "$ROOT/Backend" run check:meal-understanding >/dev/null
npm --prefix "$ROOT/Backend" run check:production-config >/dev/null
npm --prefix "$ROOT/Backend" test >/dev/null

xcodebuild \
  -project "$ROOT/Diafit.xcodeproj" \
  -scheme Diafit \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_SOURCE_FILE_NAMES=Daylight.metal \
  >/dev/null

APP="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Diafit.app"
[ -f "$APP/Info.plist" ] || fail 'Release app was not produced'
[ -f "$APP/PrivacyInfo.xcprivacy" ] || fail 'Release privacy manifest was not copied'

if plutil -p "$APP/Info.plist" | grep -q 'NSLocalNetworkUsageDescription'; then
  fail 'Release app contains a local-network usage description'
fi

printf '%s\n' 'release audit passed (unsigned simulator build; physical signing/archive remains a release step)'
