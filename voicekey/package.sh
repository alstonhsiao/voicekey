#!/usr/bin/env bash
# VoiceKey Release build + ad-hoc code signing (self-use distribution).
# Notarization is intentionally out of scope (needs a paid Apple Developer account).
# Same DerivedData rule as build.sh (must be outside the iCloud-synced project dir).
set -euo pipefail
cd "$(dirname "$0")"

DD="${VOICEKEY_DD:-$HOME/Library/Developer/VoiceKey-DD}"
APP="$DD/Build/Products/Release/VoiceKey.app"

# build 號 = git commit 數，讓每個 build 可對回 commit（選單「關於」會顯示）。
BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "▶︎ Generating project + Release build… (build $BUILD_NUM)"
xcodegen generate
xcodebuild -project VoiceKey.xcodeproj \
  -scheme VoiceKey \
  -configuration Release \
  -derivedDataPath "$DD" \
  CURRENT_PROJECT_VERSION="$BUILD_NUM" \
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
