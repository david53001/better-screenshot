#!/bin/bash
# Assemble the runnable BetterScreenshot.app bundle from the SwiftPM executable.
# Replaces the plans' `xcodegen generate && xcodebuild ...` step (full Xcode is
# unavailable in this environment; only Command Line Tools are installed).
#
# Usage: scripts/build-app.sh [debug|release] [universal]   (default: debug, host arch)
#   universal — build arm64 + x86_64 slices separately and lipo them, so one
#   bundle runs on Apple Silicon and Intel Macs. (SwiftPM's own multi-arch
#   `--arch a --arch b` needs Xcode's xcbuild, which the CLT lacks.)
#
# BETTERSCREENSHOT_APP           destination (default dist/BetterScreenshot.app; the Sparkle
#                                end-to-end test builds into its own scratch folder).
# BETTERSCREENSHOT_SWIFT_FLAGS   extra `swift build` arguments (the end-to-end test uses this).
# BETTERSCREENSHOT_REQUIRE_IDENTITY=1   fail instead of signing ad-hoc (package-release.sh sets it).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk-env.sh

CONFIG="${1:-debug}"
APP_NAME="BetterScreenshot"
# shellcheck disable=SC2206
FLAGS=(${BETTERSCREENSHOT_SWIFT_FLAGS:-})

if [ "${2:-}" = "universal" ]; then
    SLICES=()
    for TRIPLE in arm64-apple-macosx x86_64-apple-macosx; do
        echo "==> swift build -c $CONFIG --triple $TRIPLE"
        swift build -c "$CONFIG" --triple "$TRIPLE" ${FLAGS[@]+"${FLAGS[@]}"}
        BIN_DIR="$(swift build -c "$CONFIG" --triple "$TRIPLE" ${FLAGS[@]+"${FLAGS[@]}"} --show-bin-path)"
        SLICES+=("$BIN_DIR/$APP_NAME")
    done
    # Next to the slices' build folders (honours a --scratch-path in FLAGS).
    UNIVERSAL_DIR="$(dirname "$(dirname "$BIN_DIR")")/universal"
    mkdir -p "$UNIVERSAL_DIR"
    BIN="$UNIVERSAL_DIR/$APP_NAME"
    lipo -create "${SLICES[@]}" -output "$BIN"
    echo "==> lipo: $(lipo -archs "$BIN")"
else
    echo "==> swift build -c $CONFIG"
    swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"}
    BIN_DIR="$(swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"} --show-bin-path)"
    BIN="$BIN_DIR/$APP_NAME"
fi
if [ ! -x "$BIN" ]; then
    echo "error: built executable not found at $BIN" >&2
    exit 1
fi

APP="${BETTERSCREENSHOT_APP:-dist/$APP_NAME.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp App/Info.plist "$APP/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Sparkle (auto-updates): the executable finds it through its @executable_path/../Frameworks
# rpath (Package.swift). The binary target is one universal framework, the same in every
# slice's bin folder; ditto keeps its symlinks. Its XPC services are only for sandboxed apps
# (BetterScreenshot isn't; Sparkle's docs say they may be removed then), so they go, and so do
# its headers and module map (only for compiling against it, as Xcode's "strip headers" does
# when embedding). sign-app.sh re-signs the framework afterwards.
FW="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$FW"
for DIR in XPCServices Headers PrivateHeaders Modules; do
    rm -rf "${FW:?}/$DIR" "${FW:?}/Versions/B/$DIR"
done

# SwiftPM also bakes in rpaths to folders on this Mac: its build folder (searched first) and the
# Command Line Tools' Swift folders. Sparkle is the only @rpath library (the Swift runtime is in
# /usr/lib/swift since macOS 12), so drop every absolute rpath except /usr/lib/swift: the app can
# only load the embedded Sparkle and carries no path from this Mac. (Universal binaries: every
# slice is checked.)
EXE="$APP/Contents/MacOS/$APP_NAME"
for ARCH in $(lipo -archs "$EXE"); do
    if otool -arch "$ARCH" -L "$EXE" | awk 'NR > 1 { print $1 }' | grep '^@rpath/' | grep -qv '^@rpath/Sparkle.framework/'; then
        echo "error: a new @rpath library needs one of the rpaths removed below:" >&2
        otool -arch "$ARCH" -L "$EXE" | grep '@rpath/' >&2
        exit 1
    fi
    otool -arch "$ARCH" -l "$EXE" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' |
    while read -r RPATH; do
        case "$RPATH" in
            /usr/lib/swift) ;;
            /*) install_name_tool -delete_rpath "$RPATH" "$EXE" ;;   # every slice that has it
        esac
    done
done

# Signs inside-out with the stable identity from scripts/setup-signing.sh when present (so the
# Screen Recording permission persists across rebuilds and updates), else ad-hoc.
scripts/sign-app.sh "$APP"
echo "==> Built $APP"
