#!/bin/bash
# One-line installer for BetterScreenshot (macOS 14+, Apple Silicon or Intel):
#
#   curl -fsSL https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/install.sh | bash
#
# Downloads the latest GitHub release, puts BetterScreenshot.app in /Applications,
# removes the quarantine flag (the app is self-signed, not notarized — this
# project has no paid Apple Developer account, so Gatekeeper would otherwise
# refuse to open it), and launches it.
set -euo pipefail

REPO="david53001/better-screenshot"
ASSET="BetterScreenshot.app.zip"
DEST="/Applications/BetterScreenshot.app"

if [ "$(uname -s)" != "Darwin" ]; then echo "BetterScreenshot is a macOS app." >&2; exit 1; fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 14 ]; then echo "BetterScreenshot needs macOS 14 (Sonoma) or newer; you have $(sw_vers -productVersion)." >&2; exit 1; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading latest release..."
curl -fsSL -o "$TMP/$ASSET" "https://github.com/$REPO/releases/latest/download/$ASSET"
ditto -x -k "$TMP/$ASSET" "$TMP"
[ -d "$TMP/BetterScreenshot.app" ] || { echo "error: archive did not contain BetterScreenshot.app" >&2; exit 1; }

if pgrep -xq BetterScreenshot; then
    echo "==> Quitting the running copy..."
    osascript -e 'tell application "BetterScreenshot" to quit' >/dev/null 2>&1 || pkill -x BetterScreenshot || true
    sleep 1
fi

echo "==> Installing to ${DEST}..."
rm -rf "$DEST"
ditto "$TMP/BetterScreenshot.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching..."
open -a "$DEST"
echo "Done. Look for the camera icon in your menu bar; the first launch asks for Screen Recording permission."
