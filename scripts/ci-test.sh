#!/usr/bin/env bash
# Generates the Xcode project and runs the unit tests on an iPhone simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

DEVICE_ID=$(xcrun simctl list devices available -j \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for k,v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone")))')
echo "Using simulator $DEVICE_ID"

xcodebuild test \
  -project ShazamSpotifySync.xcodeproj \
  -scheme ShazamSpotifySync \
  -destination "id=$DEVICE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  | tee build.log | grep -E "error:|warning: .*(Swift|swift)|Test Case|\*\* (BUILD|TEST)" || true

grep -q "\*\* TEST SUCCEEDED \*\*" build.log
