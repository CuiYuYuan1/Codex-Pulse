#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:?usage: sign-macos-app.sh /path/to/CodexPulse.app [signing-identity]}"
SIGNING_IDENTITY="${2:--}"
WIDGET_PATH="$APP_PATH/Contents/PlugIns/CodexPulseWidget.appex"
MAIN_EXECUTABLE="$APP_PATH/Contents/MacOS/CodexPulse"
WIDGET_EXECUTABLE="$WIDGET_PATH/Contents/MacOS/CodexPulseWidget"
SIGNING_OPTIONS=(
  --force
  --sign "$SIGNING_IDENTITY"
  --timestamp=none
)

# Hardened Runtime enforces same-Team-ID library validation. Ad-hoc code has no
# stable Team ID, so enabling it makes Xcode's debug dylibs unloadable. Real
# Developer ID releases keep Hardened Runtime; local/CI ad-hoc builds do not.
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  SIGNING_OPTIONS+=(--options runtime)
fi

test -d "$APP_PATH" || {
  echo "签名失败：没有找到 $APP_PATH" >&2
  exit 1
}

# xcodebuild with CODE_SIGNING_ALLOWED=NO leaves only a linker signature. That
# signature reports the executable name ("CodexPulse") as its identity and does
# not bind Info.plist, so macOS TCC treats it as a different application from
# the com.codexpulse.app entry shown in System Settings.
#
# Debug builds also contain injected dylibs. They must be signed with the same
# identity before their containing bundles, otherwise dyld rejects them because
# the process and mapped code have different Team IDs.
find "$APP_PATH/Contents" -type f -perm -111 -print0 |
  while IFS= read -r -d '' code_path; do
    if [[ "$code_path" == "$MAIN_EXECUTABLE" ||
          "$code_path" == "$WIDGET_EXECUTABLE" ]]; then
      continue
    fi
    if file "$code_path" | grep -q 'Mach-O'; then
      codesign \
        "${SIGNING_OPTIONS[@]}" \
        "$code_path"
    fi
  done

if [[ -d "$WIDGET_PATH" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign \
      "${SIGNING_OPTIONS[@]}" \
      --identifier com.codexpulse.app.widget \
      "$WIDGET_PATH"
  else
    codesign \
      "${SIGNING_OPTIONS[@]}" \
      --identifier com.codexpulse.app.widget \
      --entitlements "$ROOT_DIR/CodexPulseWidget/CodexPulseWidget.entitlements" \
      "$WIDGET_PATH"
  fi
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign \
    "${SIGNING_OPTIONS[@]}" \
    --identifier com.codexpulse.app \
    "$APP_PATH"
else
  codesign \
    "${SIGNING_OPTIONS[@]}" \
    --identifier com.codexpulse.app \
    --entitlements "$ROOT_DIR/CodexPulse/Resources/CodexPulse.entitlements" \
    "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNATURE_IDENTIFIER="$(
  codesign -d --verbose=4 "$APP_PATH" 2>&1 |
    sed -n 's/^Identifier=//p' |
    head -1
)"
PLIST_IDENTIFIER="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$APP_PATH/Contents/Info.plist"
)"

if [[ "$SIGNATURE_IDENTIFIER" != "com.codexpulse.app" ||
      "$PLIST_IDENTIFIER" != "com.codexpulse.app" ]]; then
  echo "签名失败：TCC 身份不一致（signature=$SIGNATURE_IDENTIFIER, plist=$PLIST_IDENTIFIER）" >&2
  exit 1
fi

echo "已签名 TCC 身份：com.codexpulse.app"
