#!/usr/bin/env bash
# VoiceKey headless test helper. Same DerivedData rule as build.sh.
set -euo pipefail
cd "$(dirname "$0")"

DD="${VOICEKEY_DD:-$HOME/Library/Developer/VoiceKey-DD}"

# Tests do not need a signed .app. Forcing codesign here can hang on a
# locked login keychain; unit tests historically run with signing disabled.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate
xcodebuild -project VoiceKey.xcodeproj \
  -scheme VoiceKey \
  -configuration Debug \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO \
  test
