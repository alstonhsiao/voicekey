#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_SOURCE="${1:-$HOME/Library/Developer/VoiceKey-DD-Adhoc/Build/Products/Release/VoiceKey.app}"
DIST_DIR="$PWD/dist"
DATE_TAG="$(date +%Y%m%d)"
BASE_NAME="VoiceKey-macOS-${DATE_TAG}"
STAGE_DIR="$DIST_DIR/$BASE_NAME"
DMG_DIR="$DIST_DIR/_dmg"
ZIP_PATH="$DIST_DIR/${BASE_NAME}.zip"
DMG_PATH="$DIST_DIR/${BASE_NAME}.dmg"

if [ ! -d "$APP_SOURCE" ]; then
  echo "App not found: $APP_SOURCE" >&2
  echo "Pass the built app path as the first argument if needed." >&2
  exit 1
fi

rm -rf "$STAGE_DIR" "$DMG_DIR" "$ZIP_PATH" "$DMG_PATH"
mkdir -p "$STAGE_DIR" "$DMG_DIR"

ditto "$APP_SOURCE" "$STAGE_DIR/VoiceKey.app"
cp "$DIST_DIR/INSTALL-zh-TW.md" "$STAGE_DIR/"
cp "$DIST_DIR/env.local.example" "$STAGE_DIR/"

ditto -c -k --norsrc --keepParent "$STAGE_DIR" "$ZIP_PATH"

ditto "$APP_SOURCE" "$DMG_DIR/VoiceKey.app"
cp "$DIST_DIR/INSTALL-zh-TW.md" "$DMG_DIR/"
cp "$DIST_DIR/env.local.example" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create \
  -volname "VoiceKey" \
  -srcfolder "$DMG_DIR" \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "ZIP: $ZIP_PATH"
echo "DMG: $DMG_PATH"
