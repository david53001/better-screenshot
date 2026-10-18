#!/bin/bash
# End-to-end test of Sparkle auto-updates, on a throwaway copy of BetterScreenshot (docs/sparkle-updates/README.md):
#
#   scripts/sparkle-e2e-test.sh [work-dir]          (default: a new temp dir; deleted at the end
#                                                    unless KEEP=1)
#   E2E_UI=1 scripts/sparkle-e2e-test.sh [work-dir] (Sparkle's real windows instead; see below)
#
# 1. builds BetterScreenshot once (debug, this Mac's architecture) with -DSPARKLE_E2E_TEST: logs
#    Sparkle's steps, installs right away instead of on quit, and starts nothing but the updater
#    (no status item, hotkeys, native-shortcut changes, history or temp-file sweeps, which would
#    touch the real copy's shared state)
# 2. makes two copies with bundle id com.betterscreenshot.mac.sparkletest: OLD (build 100) and NEW
#    (build 101), both with SUFeedURL = a python http.server on 127.0.0.1 only, signed inside-out
#    with the real identity; NEW is zipped and EdDSA-signed with the real Sparkle key
# 3. GOOD: OLD runs, finds NEW in the local appcast, downloads, verifies, installs, relaunches;
#    checks the installed bundle is build 101 and passes codesign --verify --deep --strict
# 4. BAD: same with an appcast whose signature doesn't match the zip; checks it is refused and
#    the installed copy stays build 100
#
# E2E_UI=1 replaces 3-4 with the path real users take (OLD without SUAutomaticallyUpdate, run with
# SPARKLE_E2E_UI=1, App/Lifecycle/SparkleE2EUI.swift): the scheduled check's window must open —
# in front if Sparkle chose "immediate focus" (app launched just now, or the Mac idle; then its
# user-attention callback must clear our menu label), otherwise behind other windows without
# focus and with the menu reading "Update Available (90.1)…" — then it clicks Install Update and
# Install and Relaunch in Sparkle's own windows and checks the installed copy is build 101. The test app's windows are transparent (nothing shows on screen);
# snapshots of them land in <work-dir>/ui/ (KEEP=1 to keep them).
#
# Never touches the real BetterScreenshot (/Applications or dist/), its bundle id's defaults or
# a running copy: everything is keyed by the test bundle id and the work dir's path. Quits what
# it started and removes the test bundle id's defaults, caches and Launch Services entries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Developer/Sparkle/2.10.0/bin}"
TEST_ID="com.betterscreenshot.mac.sparkletest"
PORT="${PORT:-8766}"
WORK="${1:-$(mktemp -d)}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd -P)"
INSTALL="$WORK/install/BetterScreenshot.app"
FEED="$WORK/feed"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
SERVER_PID=""

say() { printf '\n==> %s\n' "$*"; }

stop_test_apps() {
    # Only processes running from this work dir or Sparkle's per-app cache for the test id.
    pkill -f "$WORK/install/BetterScreenshot.app/" 2>/dev/null || true
    pkill -f "Caches/$TEST_ID/" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$WORK/install/BetterScreenshot.app/" >/dev/null || break
        sleep 0.5
    done
}

reset_test_state() {
    defaults delete "$TEST_ID" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$TEST_ID.plist"
    rm -rf "$HOME/Library/Caches/$TEST_ID" "$HOME/Library/HTTPStorages/$TEST_ID" \
           "$HOME/Library/HTTPStorages/$TEST_ID.binarycookies" \
           "$HOME/Library/Saved Application State/$TEST_ID.savedState"
}

cleanup() {
    set +e
    stop_test_apps
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    reset_test_state
    [ -x "$LSREGISTER" ] && for app in "$WORK"/*/BetterScreenshot.app; do [ -d "$app" ] && "$LSREGISTER" -u "$app" 2>/dev/null; done
    if [ "${KEEP:-0}" != 1 ]; then rm -rf "$WORK"; else echo "kept $WORK"; fi
}
trap cleanup EXIT

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "error: port $PORT is in use; set PORT=..." >&2; exit 1
fi

say "build (SPARKLE_E2E_TEST) into $WORK/stage"
BETTERSCREENSHOT_APP="$WORK/stage/BetterScreenshot.app" BETTERSCREENSHOT_REQUIRE_IDENTITY=1 \
    BETTERSCREENSHOT_SWIFT_FLAGS="--scratch-path $WORK/build -Xswiftc -DSPARKLE_E2E_TEST" \
    "$ROOT/scripts/build-app.sh" debug >"$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }

# make_variant <build> <version> <dest> [automatic-update: 1 (default) or 0]
make_variant() {
    local dest="$3/BetterScreenshot.app" plist="$3/BetterScreenshot.app/Contents/Info.plist"
    mkdir -p "$3"
    ditto "$WORK/stage/BetterScreenshot.app" "$dest"
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleIdentifier $TEST_ID" \
        -c "Set :CFBundleVersion $1" \
        -c "Set :CFBundleShortVersionString $2" \
        -c "Set :SUFeedURL http://127.0.0.1:$PORT/appcast.xml" \
        -c "Add :NSAppTransportSecurity dict" \
        -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" \
        "$plist"
    if [ "${4:-1}" = 1 ]; then /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool true" "$plist"; fi
    BETTERSCREENSHOT_REQUIRE_IDENTITY=1 "$ROOT/scripts/sign-app.sh" "$dest" >/dev/null 2>&1
}

# write_appcast <zip> <edSignature attrs>
write_appcast() {
    cat > "$FEED/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>BetterScreenshot (end-to-end test)</title>
    <item>
      <title>BetterScreenshot 90.1 (test)</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>101</sparkle:version>
      <sparkle:shortVersionString>90.1</sparkle:shortVersionString>
      <description sparkle:format="markdown"><![CDATA[Test update.]]></description>
      <enclosure url="http://127.0.0.1:$PORT/$(basename "$1")" type="application/octet-stream" $2 />
    </item>
  </channel>
</rss>
XML
}

installed_build() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL/Contents/Info.plist"; }

# run_old <log> <seconds> [ui: 0 (default) or 1]: launch OLD, wait until the installed copy is NEW
# or time runs out.
run_old() {
    local ui="${3:-0}" auto=1
    [ "$ui" = 1 ] && auto=0
    rm -rf "$WORK/install" && make_variant 100 90.0 "$WORK/install" "$auto"
    reset_test_state
    # Make the daily check due right away (no "may we check?" dialog: SUEnableAutomaticChecks).
    defaults write "$TEST_ID" SULastCheckTime -date "2000-01-01 00:00:00 +0000"
    echo "launching OLD: build $(installed_build), $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL/Contents/Info.plist"), UI mode $ui"
    SPARKLE_E2E_UI="$ui" SPARKLE_E2E_SNAP_DIR="$WORK/ui" "$INSTALL/Contents/MacOS/BetterScreenshot" >"$1" 2>&1 &
    local pid=$! waited=0
    sleep 0.7
    echo "OLD pid $pid loads Sparkle from: $(vmmap "$pid" 2>/dev/null | grep -o '/[^ ]*Sparkle.framework/Versions/B/Sparkle' | sort -u || true)"
    while [ "$waited" -lt "$2" ] && [ "$(installed_build)" = 100 ] && ! grep -q 'SPARKLE-E2E aborted' "$1"; do
        sleep 1; waited=$((waited + 1))
    done
    sleep 3   # let the relaunch happen
    echo "after ${waited}s: installed build $(installed_build)"
    grep -o 'SPARKLE-E2E.*' "$1" || true
}

mkdir -p "$FEED"
make_variant 101 90.1 "$WORK/new"
ditto -c -k --keepParent "$WORK/new/BetterScreenshot.app" "$FEED/BetterScreenshot-good.zip"
GOOD_ATTRS="$("$SPARKLE_BIN/sign_update" "$FEED/BetterScreenshot-good.zip")"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FEED" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
sleep 1

if [ "${E2E_UI:-0}" = 1 ]; then
    say "UI: signed update 100 -> 101 through Sparkle's own windows"
    write_appcast "$FEED/BetterScreenshot-good.zip" "$GOOD_ATTRS"
    run_old "$WORK/ui.log" 120 1
    UI_RESULT="$(installed_build)"
    stop_test_apps
    say "RESULT (UI mode)"
    PASS=1
    check() {   # check <description> <grep pattern in the log>
        if grep -q -- "$2" "$WORK/ui.log"; then echo "$1: PASS"; else echo "$1: FAIL"; PASS=0; fi
    }
    check "update window shown by the scheduled check" "SPARKLE-E2E UI update window shown"
    # Sparkle shows a scheduled update in "immediate focus" when the app was launched recently or
    # the Mac had been idle (both true here unless someone is using the Mac); otherwise behind
    # other windows, with our menu naming it. Each path has its own expectations.
    if grep -q "SPARKLE-E2E UI scheduled update 90.1, immediate focus 1" "$WORK/ui.log"; then
        echo "(Sparkle chose immediate focus: launched just now / Mac idle $(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}') s)"
        check "in focus: Sparkle reports the user's attention" "SPARKLE-E2E UI user attention for 90.1"
        check "in focus: the menu doesn't nag (Check for Updates…)" "SPARKLE-E2E UI menu title: Check for Updates…"
    else
        echo "(Sparkle chose the background: behind other windows)"
        check "behind: it took no focus (not key, app not active)" "SPARKLE-E2E UI update window shown: key 0, app active 0"
        check "behind: the menu reads Update Available (90.1)…" "SPARKLE-E2E UI menu title: Update Available (90.1)…"
    fi
    check "the menu action leaves nothing pending" "SPARKLE-E2E UI after the menu action: pending none"
    check "Install and Relaunch was offered and clicked" "SPARKLE-E2E UI clicking Install and Relaunch"
    if [ "$UI_RESULT" = 101 ]; then echo "installed and relaunched as build 101: PASS"; else echo "installed copy is build $UI_RESULT: FAIL"; PASS=0; fi
    ls "$WORK/ui"/*.png 2>/dev/null || echo "(no snapshots)"
    [ "$PASS" = 1 ]
    exit
fi

say "GOOD: signed update 100 -> 101"
write_appcast "$FEED/BetterScreenshot-good.zip" "$GOOD_ATTRS"
run_old "$WORK/good.log" 90
GOOD_RESULT="$(installed_build)"
if [ "$GOOD_RESULT" = 101 ]; then
    codesign --verify --deep --strict "$INSTALL" && echo "installed copy: codesign --verify --deep --strict OK"
    codesign -dvv "$INSTALL" 2>&1 | grep -E '^(Identifier|Authority)='
    echo "running after relaunch:"; pgrep -fl "$WORK/install/BetterScreenshot.app/Contents/MacOS/BetterScreenshot" || echo "(not relaunched)"
fi
stop_test_apps

say "BAD: zip whose EdDSA signature doesn't match"
# Same zip and length, but the signature of different bytes (the OLD copy zipped).
ditto -c -k --keepParent "$WORK/install/BetterScreenshot.app" "$WORK/other.zip"
BAD_SIG="$("$SPARKLE_BIN/sign_update" -p "$WORK/other.zip")"
cp "$FEED/BetterScreenshot-good.zip" "$FEED/BetterScreenshot-bad.zip"
write_appcast "$FEED/BetterScreenshot-bad.zip" "sparkle:edSignature=\"$BAD_SIG\" length=\"$(stat -f %z "$FEED/BetterScreenshot-bad.zip")\""
run_old "$WORK/bad.log" 45
BAD_RESULT="$(installed_build)"
stop_test_apps

say "server requests"
cat "$WORK/server.log"

say "RESULT"
PASS=1
if [ "$GOOD_RESULT" = 101 ]; then echo "GOOD update installed (build 101): PASS"; else echo "GOOD update NOT installed (build $GOOD_RESULT): FAIL"; PASS=0; fi
if [ "$BAD_RESULT" = 100 ]; then echo "BAD signature refused (still build 100): PASS"; else echo "BAD signature installed (build $BAD_RESULT): FAIL"; PASS=0; fi
[ "$PASS" = 1 ]
