#!/usr/bin/env bash
# 將已建好的 VoiceKey.app 打成可跨機分發的 zip / dmg。
# 預設取 package.sh 的 Release 產物路徑；也可用第一個參數覆寫。
set -euo pipefail

cd "$(dirname "$0")"

DD="${VOICEKEY_DD:-$HOME/Library/Developer/VoiceKey-DD}"
APP_SOURCE="${1:-$DD/Build/Products/Release/VoiceKey.app}"
DIST_DIR="$PWD/dist"
DATE_TAG="$(date +%Y%m%d)"
BASE_NAME="VoiceKey-macOS-${DATE_TAG}"
STAGE_DIR="$DIST_DIR/$BASE_NAME"
DMG_DIR="$DIST_DIR/_dmg"
ZIP_PATH="$DIST_DIR/${BASE_NAME}.zip"
DMG_PATH="$DIST_DIR/${BASE_NAME}.dmg"

if [ ! -d "$APP_SOURCE" ]; then
  echo "App not found: $APP_SOURCE" >&2
  echo "先跑 ./package.sh，或把 .app 路徑當第一個參數傳入。" >&2
  exit 1
fi

# 清掉本次暫存與同日產物；一併移除歷史 WhisperVoice 分發殘留
rm -rf "$STAGE_DIR" "$DMG_DIR" "$ZIP_PATH" "$DMG_PATH"
rm -rf "$DIST_DIR"/WhisperVoice-macOS-* "$DIST_DIR"/_dmg
# 勿刪 INSTALL / env.local.example / INDEX.md
find "$DIST_DIR" -maxdepth 1 -type d -name 'WhisperVoice*' -exec rm -rf {} + 2>/dev/null || true
find "$DIST_DIR" -maxdepth 1 \( -name 'WhisperVoice*.zip' -o -name 'WhisperVoice*.dmg' \) -delete 2>/dev/null || true

mkdir -p "$STAGE_DIR" "$DMG_DIR"

echo "▶︎ Staging from: $APP_SOURCE"
ditto "$APP_SOURCE" "$STAGE_DIR/VoiceKey.app"
cp "$DIST_DIR/INSTALL-zh-TW.md" "$STAGE_DIR/"
cp "$DIST_DIR/env.local.example" "$STAGE_DIR/"

echo "▶︎ ZIP…"
ditto -c -k --norsrc --keepParent "$STAGE_DIR" "$ZIP_PATH"

echo "▶︎ DMG…"
ditto "$APP_SOURCE" "$DMG_DIR/VoiceKey.app"
cp "$DIST_DIR/INSTALL-zh-TW.md" "$DMG_DIR/"
cp "$DIST_DIR/env.local.example" "$DMG_DIR/"
ln -sf /Applications "$DMG_DIR/Applications"

hdiutil create \
  -volname "VoiceKey" \
  -srcfolder "$DMG_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

# 簡單內容檢查
APP_BIN="$STAGE_DIR/VoiceKey.app/Contents/MacOS/VoiceKey"
if [ ! -x "$APP_BIN" ]; then
  echo "❌ 預期可執行檔不存在: $APP_BIN" >&2
  exit 1
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGE_DIR/VoiceKey.app/Contents/Info.plist" 2>/dev/null || true)"
if [ "$BUNDLE_ID" != "com.alston.VoiceKey" ]; then
  echo "❌ bundle id 異常: ${BUNDLE_ID:-empty}（應為 com.alston.VoiceKey）" >&2
  exit 1
fi

echo ""
echo "✅ ZIP: $ZIP_PATH"
echo "✅ DMG: $DMG_PATH"
echo "   App: VoiceKey.app  bundle=$BUNDLE_ID"
echo "   跨機：解壓/掛載 → 拖進 /Applications → 見 INSTALL-zh-TW.md"
