#!/usr/bin/env bash
# VoiceKey Release build + ad-hoc code signing (self-use distribution).
# Notarization is intentionally out of scope (needs a paid Apple Developer account).
# Same DerivedData rule as build.sh (must be outside the iCloud-synced project dir).
set -euo pipefail
cd "$(dirname "$0")"

DD="${VOICEKEY_DD:-$HOME/Library/Developer/VoiceKey-DD}"
APP="$DD/Build/Products/Release/VoiceKey.app"

echo "▶︎ Generating project + Release build…"
xcodegen generate
xcodebuild -project VoiceKey.xcodeproj \
  -scheme VoiceKey \
  -configuration Release \
  -derivedDataPath "$DD" \
  build

echo "▶︎ Signing with self-signed identity…"
# 用 self-signed 憑證（非 ad-hoc），讓輔助使用授權在 rebuild 後不掉。
# 若憑證不存在，先跑 bash setup-signing-cert.sh。
codesign --force --deep --sign "VoiceKey Self-Signed" "$APP"

echo "▶︎ Verifying signature…"
codesign -dv "$APP" 2>&1 | sed -n '1,8p' || true
codesign --verify --deep --strict "$APP" && echo "✅ 簽章驗證通過"

echo ""
echo "✅ App: $APP"
echo "   分發到其他 Mac 後，首次右鍵 → 開啟，或："
echo "   xattr -dr com.apple.quarantine /Applications/VoiceKey.app"
