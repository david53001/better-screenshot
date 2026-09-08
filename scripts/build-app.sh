#!/bin/bash
# Assemble the runnable BetterScreenshot.app bundle from the SwiftPM executable.
# Replaces the plans' `xcodegen generate && xcodebuild ...` step (full Xcode is
# unavailable in this environment; only Command Line Tools are installed).
#
# Usage: scripts/build-app.sh [debug|release] [universal]   (default: debug, host arch)
#   universal — build arm64 + x86_64 slices separately and lipo them, so one
#   bundle runs on Apple Silicon and Intel Macs. (SwiftPM's own multi-arch
#   `--arch a --arch b` needs Xcode's xcbuild, which the CLT lacks.)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="BetterScreenshot"

if [ "${2:-}" = "universal" ]; then
    SLICES=()
    for TRIPLE in arm64-apple-macosx x86_64-apple-macosx; do
        echo "==> swift build -c $CONFIG --triple $TRIPLE"
        swift build -c "$CONFIG" --triple "$TRIPLE"
        SLICES+=("$(swift build -c "$CONFIG" --triple "$TRIPLE" --show-bin-path)/$APP_NAME")
    done
    mkdir -p .build/universal
    BIN=".build/universal/$APP_NAME"
    lipo -create "${SLICES[@]}" -output "$BIN"
    echo "==> lipo: $(lipo -archs "$BIN")"
else
    echo "==> swift build -c $CONFIG"
    swift build -c "$CONFIG"
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
fi
if [ ! -x "$BIN" ]; then
    echo "error: built executable not found at $BIN" >&2
    exit 1
fi

DIST="dist"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp App/Info.plist "$APP/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Sign (non-sandboxed; entitlements file has no sandbox key). Prefer the stable
# self-signed identity from scripts/setup-signing.sh so Screen-Recording (TCC)
# permission persists across rebuilds; otherwise fall back to ad-hoc.
SIGN_IDENTITY="BetterScreenshot Code Signing"
SIGN_KEYCHAIN="$HOME/Library/Keychains/betterscreenshot-signing.keychain-db"
SIGN_KEYCHAIN_PW="betterscreenshot-local"

if security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    security unlock-keychain -p "$SIGN_KEYCHAIN_PW" "$SIGN_KEYCHAIN" 2>/dev/null || true
    if codesign --force --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY" \
            --entitlements App/BetterScreenshot.entitlements "$APP" >/dev/null 2>&1; then
        echo "==> Built $APP (signed with stable identity — permissions persist)"
        exit 0
    fi
    echo "warning: stable signing failed; falling back to ad-hoc" >&2
fi

codesign --force --sign - --entitlements App/BetterScreenshot.entitlements "$APP" >/dev/null 2>&1 \
    || codesign --force --sign - "$APP" >/dev/null 2>&1
echo "==> Built $APP (ad-hoc; run scripts/setup-signing.sh for persistent permissions)"
