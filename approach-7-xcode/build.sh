#!/usr/bin/env bash
# WhisperVoice headless build helper.
#
# 重要：DerivedData 必須放在 iCloud 同步目錄（~/Documents）之外，否則 build 產物的
# .app 會被加上 com.apple.FinderInfo / com.apple.fileprovider 擴充屬性，導致
# codesign 失敗（"resource fork, Finder information, or similar detritus not allowed"）。
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-Debug}"
DD="${WHISPERVOICE_DD:-$HOME/Library/Developer/WhisperVoice-DD}"

xcodegen generate
xcodebuild -project WhisperVoice.xcodeproj \
  -scheme WhisperVoice \
  -configuration "$CONFIG" \
  -derivedDataPath "$DD" \
  build

echo ""
echo "✅ App: $DD/Build/Products/$CONFIG/WhisperVoice.app"
