#!/usr/bin/env bash
# VoiceKey headless build helper.
#
# 重要：DerivedData 必須放在 iCloud 同步目錄（~/Documents）之外，否則 build 產物的
# .app 會被加上 com.apple.FinderInfo / com.apple.fileprovider 擴充屬性，導致
# codesign 失敗（"resource fork, Finder information, or similar detritus not allowed"）。
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-Debug}"
DD="${VOICEKEY_DD:-$HOME/Library/Developer/VoiceKey-DD}"

# build 號 = git commit 數，讓每個 build 可對回 commit（選單「關於」會顯示）。
# 注意：專案若在 iCloud 同步目錄，git 可能無限卡住，故用 timeout 兜底。
BUILD_NUM="$(perl -e 'alarm 5; exec @ARGV' git rev-list --count HEAD 2>/dev/null || echo 1)"

xcodegen generate
xcodebuild -project VoiceKey.xcodeproj \
  -scheme VoiceKey \
  -configuration "$CONFIG" \
  -derivedDataPath "$DD" \
  CURRENT_PROJECT_VERSION="$BUILD_NUM" \
  build

echo ""
echo "✅ App: $DD/Build/Products/$CONFIG/VoiceKey.app"
