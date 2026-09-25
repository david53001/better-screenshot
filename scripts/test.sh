#!/bin/bash
# Runs every package's TestKit suite. Each runner exits non-zero on failure,
# and set -e makes the first failure fail the whole script.
set -euo pipefail
cd "$(dirname "$0")/.."
for pkg in CaptureKit OverlayKit EditorKit RecordingKit HistoryKit TourKit; do
    echo "== ${pkg}Tests"
    swift run --package-path "Packages/$pkg" "${pkg}Tests"
done
echo "All suites passed."
