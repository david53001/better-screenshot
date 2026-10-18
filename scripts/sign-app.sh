#!/bin/bash
# Signs an assembled BetterScreenshot.app inside-out: Sparkle's nested helpers, then the
# framework, then the app (no --deep: it would re-sign the helpers without their own options).
#
#   scripts/sign-app.sh path/to/BetterScreenshot.app
#
# Uses the stable "BetterScreenshot Code Signing" identity from scripts/setup-signing.sh, so the
# Screen Recording permission survives every rebuild and update; without it, falls back to ad-hoc
# with a warning, or fails when BETTERSCREENSHOT_REQUIRE_IDENTITY=1 (releases, the e2e test).
# Sparkle's helpers keep the hardened runtime they ship with (they load only system libraries);
# the app itself stays without it, as before: it is not sandboxed or notarized, and the
# runtime's library validation would refuse a Sparkle.framework signed by a self-signed cert.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"
ENTITLEMENTS="App/BetterScreenshot.entitlements"

IDENTITY="BetterScreenshot Code Signing"
KEYCHAIN="$HOME/Library/Keychains/betterscreenshot-signing.keychain-db"
KEYCHAIN_PW="betterscreenshot-local"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN" 2>/dev/null || true
    SIGN=(--keychain "$KEYCHAIN" --sign "$IDENTITY")
    WHO="stable identity '$IDENTITY'; permissions persist"
elif [ "${BETTERSCREENSHOT_REQUIRE_IDENTITY:-0}" = 1 ]; then
    echo "error: signing identity '$IDENTITY' not found; run scripts/setup-signing.sh" >&2
    exit 1
else
    echo "warning: '$IDENTITY' not found; signing ad-hoc (run scripts/setup-signing.sh for persistent permissions)" >&2
    SIGN=(--sign -)
    WHO="ad-hoc"
fi

FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
    V="$FW/Versions/B"
    # (build-app.sh removed the XPC services: only sandboxed apps use them.)
    codesign --force "${SIGN[@]}" -o runtime "$V/Autoupdate"
    codesign --force "${SIGN[@]}" -o runtime "$V/Updater.app"
    codesign --force "${SIGN[@]}" -o runtime "$FW"
fi

# Non-sandboxed (the entitlements file has no sandbox key). Seals Info.plist + Resources +
# Frameworks: the designated requirement stays `identifier "com.betterscreenshot.mac" and
# certificate leaf = H"…"`, which is what Screen Recording (TCC) is keyed on.
codesign --force "${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed $APP ($WHO)"
