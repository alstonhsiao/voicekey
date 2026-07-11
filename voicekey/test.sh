#!/usr/bin/env bash
# VoiceKey headless test helper. Same DerivedData rule as build.sh.
set -euo pipefail
cd "$(dirname "$0")"

DD="${VOICEKEY_DD:-$HOME/Library/Developer/VoiceKey-DD}"

xcodegen generate
xcodebuild -project VoiceKey.xcodeproj \
  -scheme VoiceKey \
  -configuration Debug \
  -derivedDataPath "$DD" \
  test
