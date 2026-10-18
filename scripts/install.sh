#!/bin/bash
# One-line installer AND updater for BetterScreenshot (macOS 14+, Apple Silicon or Intel):
#
#   curl -fsSL https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/install.sh | bash
#
# Downloads the latest GitHub release, puts BetterScreenshot.app in /Applications,
# removes the quarantine flag (the app is self-signed, not notarized — this
# project has no paid Apple Developer account, so Gatekeeper would otherwise
# refuse to open it), and launches it. Run again to update: it says which version
# you had and which you got, and does nothing when you're already up to date
# (reinstall anyway with: ... | BETTERSCREENSHOT_FORCE=1 bash).
#
# It only ever replaces /Applications/BetterScreenshot.app. Settings
# (~/Library/Preferences/com.betterscreenshot.mac.plist), capture history
# (~/Library/Application Support/BetterScreenshot/History/) and the Screen
# Recording permission (tied to the bundle id + signing certificate) are never
# touched. The certificate is the same for every release except 3.2.0, which
# changed it once; then macOS asks to allow Screen Recording again and this says so.
set -euo pipefail

REPO="david53001/better-screenshot"
ASSET="BetterScreenshot.app.zip"
DEST="/Applications/BetterScreenshot.app"

version_of() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null || true; }
cert_of() { codesign -d -r- "$1" 2>&1 | grep -o 'certificate leaf = H"[0-9a-f]*"' || true; }

if [ "$(uname -s)" != "Darwin" ]; then echo "BetterScreenshot is a macOS app." >&2; exit 1; fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MAJOR" -lt 14 ]; then echo "BetterScreenshot needs macOS 14 (Sonoma) or newer; you have $(sw_vers -productVersion)." >&2; exit 1; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading latest release..."
curl -fsSL -o "$TMP/$ASSET" "https://github.com/$REPO/releases/latest/download/$ASSET"
ditto -x -k "$TMP/$ASSET" "$TMP"
[ -d "$TMP/BetterScreenshot.app" ] || { echo "error: archive did not contain BetterScreenshot.app" >&2; exit 1; }

OLD="$(version_of "$DEST")"
NEW="$(version_of "$TMP/BetterScreenshot.app")"
OLD_CERT="$(cert_of "$DEST")"
NEW_CERT="$(cert_of "$TMP/BetterScreenshot.app")"
if [ -n "$OLD" ] && [ "$OLD" = "$NEW" ] && [ "${BETTERSCREENSHOT_FORCE:-0}" != "1" ]; then
    echo "BetterScreenshot $OLD is already the latest version."
    pgrep -xq BetterScreenshot || open -a "$DEST"
    exit 0
fi

if pgrep -xq BetterScreenshot; then
    echo "==> Quitting the running copy..."
    osascript -e 'tell application "BetterScreenshot" to quit' >/dev/null 2>&1 || true
    # Wait for it to exit (a capture or recording can take a moment to finish); force it after ~10 s.
    for _ in $(seq 1 20); do pgrep -xq BetterScreenshot || break; sleep 0.5; done
    pkill -x BetterScreenshot 2>/dev/null || true
fi

echo "==> Installing to ${DEST}..."
rm -rf "$DEST"
ditto "$TMP/BetterScreenshot.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching..."
open -a "$DEST"
if [ -n "$OLD" ] && [ -n "$OLD_CERT" ] && [ "$OLD_CERT" != "$NEW_CERT" ]; then
    echo "Updated BetterScreenshot ${OLD} → ${NEW}. Your settings and history are kept."
    echo "This version is signed with a new certificate, so allow Screen Recording once more:"
    echo "System Settings → Privacy & Security → Screen & System Audio Recording: remove the old BetterScreenshot entry with −, then take a screenshot and allow it."
elif [ -n "$OLD" ]; then
    echo "Updated BetterScreenshot ${OLD} → ${NEW}. Your settings, history and permissions are kept."
else
    echo "Installed BetterScreenshot ${NEW}. Look for the camera icon in your menu bar; the first launch asks for Screen Recording permission."
fi
