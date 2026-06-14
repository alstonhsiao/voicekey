#!/usr/bin/env bash
# WhisperVoice Release build + ad-hoc code signing (self-use distribution).
# Notarization is intentionally out of scope (needs a paid Apple Developer account).
# Same DerivedData rule as build.sh (must be outside the iCloud-synced project dir).
set -euo pipefail
cd "$(dirname "$0")"

DD="${WHISPERVOICE_DD:-$HOME/Library/Developer/WhisperVoice-DD}"
APP="$DD/Build/Products/Release/WhisperVoice.app"

echo "▶︎ Generating project + Release build…"
xcodegen generate
xcodebuild -project WhisperVoice.xcodeproj \
  -scheme WhisperVoice \
  -configuration Release \
  -derivedDataPath "$DD" \
  build

echo "▶︎ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "▶︎ Verifying signature…"
codesign -dv "$APP" 2>&1 | sed -n '1,8p' || true
codesign --verify --deep --strict "$APP" && echo "✅ ad-hoc 簽章驗證通過"

echo ""
echo "✅ App: $APP"
echo "   分發到其他 Mac 後，首次右鍵 → 開啟，或："
echo "   xattr -dr com.apple.quarantine /Applications/WhisperVoice.app"
