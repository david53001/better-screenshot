#!/bin/bash
# One-line uninstaller for BetterScreenshot (macOS):
#
#   curl -fsSL https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/uninstall.sh | bash
#
# Quits BetterScreenshot and removes everything it put on this Mac: the app, its settings,
# its capture history, its caches and temp files, and its Screen Recording / Microphone /
# Camera permissions. Screenshots and recordings you saved yourself are not touched.
# Reinstall any time with scripts/install.sh.
set -euo pipefail

APP_NAME="BetterScreenshot"
BUNDLE_ID="com.betterscreenshot.mac"
APP="/Applications/BetterScreenshot.app"

if [ "$(uname -s)" != "Darwin" ]; then echo "This uninstaller is for macOS." >&2; exit 1; fi

if pgrep -xq "$APP_NAME"; then
    echo "==> Quitting $APP_NAME..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do pgrep -xq "$APP_NAME" || break; sleep 0.5; done
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

echo "==> Removing $APP..."
rm -rf "$APP"

echo "==> Removing settings, history and caches..."
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
defaults delete com.betterscreenshot.app >/dev/null 2>&1 || true   # bundle id used before v2.8.1
rm -rf "$HOME/Library/Preferences/$BUNDLE_ID.plist" \
       "$HOME/Library/Preferences/com.betterscreenshot.app.plist" \
       "$HOME/Library/Application Support/BetterScreenshot" \
       "$HOME/Library/Caches/$BUNDLE_ID" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
       "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
       "${TMPDIR:-/tmp}"/BetterScreenshot-*

echo "==> Resetting permissions..."
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Done. $APP_NAME is uninstalled."
