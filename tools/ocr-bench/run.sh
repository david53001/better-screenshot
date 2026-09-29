#!/bin/zsh
# Builds, then runs the corpus under a timeout guard and prints the summary. Extra args pass through.
cd "$(dirname "$0")"
touch Package.swift ../../Packages/CaptureKit/Package.swift; swift build > build.log 2>&1 || { grep -E "error:" build.log | sort -u; echo "BUILD FAILED"; exit 1; }
(./.build/debug/ocr-bench run "$@" > run.log 2>&1 & PID=$!; (sleep 300; kill $PID 2>/dev/null) & wait $PID)
grep -E "^\[FAIL\]" run.log | awk '{print $2}' | tr '\n' ' '; echo
sed -n '/^| Area/,/^| \*\*all/p' run.log
