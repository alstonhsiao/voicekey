#!/usr/bin/env bash
# WhisperVoice headless test helper. Same DerivedData rule as build.sh.
set -euo pipefail
cd "$(dirname "$0")"

DD="${WHISPERVOICE_DD:-$HOME/Library/Developer/WhisperVoice-DD}"

xcodegen generate
xcodebuild -project WhisperVoice.xcodeproj \
  -scheme WhisperVoice \
  -configuration Debug \
  -derivedDataPath "$DD" \
  test
