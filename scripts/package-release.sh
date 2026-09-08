#!/bin/bash
# Build the universal (Apple Silicon + Intel) release bundle and zip it for a
# GitHub release. Output: dist/BetterScreenshot.app.zip — made with ditto so the
# bundle's code signature and structure survive the round trip.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh release universal

APP="dist/BetterScreenshot.app"
ZIP="dist/BetterScreenshot.app.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> verify"
lipo -archs "$APP/Contents/MacOS/BetterScreenshot"
codesign --verify --deep --strict "$APP" && echo "signature OK"
ls -la "$ZIP"
