#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION: "\([^"]*\)".*/\1/p' project.yml | head -1)}"
ARCHS_VALUE="${ARCHS_VALUE:-arm64 x86_64}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/macos-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist/mac}"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGE_DIR="$BUILD_DIR/dmg"
APP_PATH="$DERIVED_DATA/Build/Products/Release/CodexPulse.app"
DMG_PATH="$OUTPUT_DIR/CodexPulse-macOS-${VERSION}-universal.dmg"

command -v xcodegen >/dev/null || {
  echo "缺少 xcodegen，请先执行：brew install xcodegen" >&2
  exit 1
}

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

xcodegen generate
rm -rf "$BUILD_DIR"
mkdir -p "$STAGE_DIR" "$OUTPUT_DIR"

xcodebuild \
  -project CodexPulse.xcodeproj \
  -scheme CodexPulse \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="$ARCHS_VALUE" \
  MARKETING_VERSION="$VERSION" \
  clean build

test -d "$APP_PATH" || {
  echo "打包失败：没有找到 $APP_PATH" >&2
  exit 1
}

ditto "$APP_PATH" "$STAGE_DIR/CodexPulse.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create \
  -volname "CodexPulse" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

echo "$DMG_PATH"
