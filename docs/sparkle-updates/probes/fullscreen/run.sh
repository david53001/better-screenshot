#!/bin/bash
# Checks LaunchAtLoginPrompt.fullScreenInFront against the real window server (round 3, M1):
# process A (a regular app) shows a window, zooms it, then puts it into real full screen for 4 s;
# process B (an accessory app, like BetterScreenshot) evaluates the shipped rule twice a second,
# exactly as App/MenuBar/LaunchAtLoginPromptController.swift does (and, in case the screen is
# locked, also on A's own windows as if A were frontmost).
#
#   docs/sparkle-updates/probes/fullscreen/run.sh
#
# Needs an UNLOCKED screen (locked, loginwindow is frontmost and A never really goes full screen).
# A window goes full screen on your display for about 4 s; don't type meanwhile. Each process is
# killed after 30 s at most. Builds into a temp dir, deletes it afterwards.
# Expected: "fullScreenInFront false" while A is normal or zoomed, "true" while A is full screen
# (front = probe-a), false again afterwards.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/sdk-env.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc ${SDKROOT:+-sdk "$SDKROOT"} -O -o "$TMP/probe-b" "$HERE/main.swift" \
    "$ROOT/Packages/CaptureKit/Sources/CaptureKit/LaunchAtLoginPrompt.swift"
swiftc ${SDKROOT:+-sdk "$SDKROOT"} -O -o "$TMP/probe-a" "$HERE/fullscreen-app.swift"
perl -e 'alarm 30; exec @ARGV' "$TMP/probe-b" > "$TMP/b.log" 2>&1 &
sleep 1
perl -e 'alarm 25; exec @ARGV' "$TMP/probe-a" || true
wait || true
cat "$TMP/b.log"
