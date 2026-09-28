# ocr-bench — Capture Text (OCR) corpus harness

Measures how good BetterScreenshot's **Capture Text** (⌘⇧7) clipboard output is. It renders 107
realistic images (66 original cases in `Cases.swift`, plus the re-reviewer's 35 held-out `H*` cases and 6
no-harm `N*` cases in `HeldOutCases.swift`) with known ground truth (prose, lists, code, tables, typeset math, multi-column
layouts, robustness cases), runs each through the **real** app entry point
`TextRecognizer.recognize(in:pointWidth:)` from the repo's `Packages/CaptureKit` (SwiftPM path
dependency `../../Packages/CaptureKit` — edit CaptureKit, rebuild here, rerun), and compares the
clipboard string (`RecognitionResult.clipboardString`) with what a careful human would type.

Written for the review `docs/reviews/2026-09-28-ocr-review.md`; lives in the repo at
`tools/ocr-bench/` (`.build/` and `out/` are git-ignored).
Terms: **Vision** = Apple's on-device OCR framework (`VNRecognizeTextRequest`); **TextReflow** =
the app's line→paragraph/table/code rebuilding step (`Packages/CaptureKit/Sources/CaptureKit/TextReflow.swift`);
**Live Text** = macOS's own copy-text-from-image feature, used here as a reference;
**CER** = character error rate (edit distance ÷ expected length; 0 = perfect).

Shortcut: `./run.sh [options]` (from anywhere) builds, runs every case under a timeout guard and prints
the failing case ids plus the per-area table; details land in `run.log`. New source files in CaptureKit
need the manifest touched before SwiftPM sees them — `run.sh` does that.

Split by set: `python3 summarize.py [IDS…]` (existing / held-out / no-harm, plus expected vs actual for the
given ids). **Regressions:** `python3 diff.py baselines/<file>.json [--show]` lists every case whose
pass/fail or CER moved against a saved run; save one with `cp out/results.json baselines/<name>.json`.
`run --only` overwrites `out/results.json`, so do a full run before diffing.

## Build & run (CLT only, no Xcode; run from this directory)

```sh
swift build
# Always guard runs with a timeout; never pipe the binary (then $! is the wrong PID):
(./.build/debug/ocr-bench all > run.log 2>&1 & PID=$!; (sleep 300; kill $PID) & wait $PID); tail -12 run.log
```

Commands (first argument):

| Command | What it does |
|---|---|
| `all` (default) | render any missing images, then recognize + score every case |
| `render` | (re)render the selected cases' images only |
| `run` | recognize + score (uses cached images in `out/images/`; renders missing ones) |
| `dump ID…` | raw Vision observations for those cases: boxes, top-3 candidates, per-character boxes, with language correction on **and** off, plus the final clipboard string |
| `probes` | Vision-free reproductions of the TextReflow root causes (synthetic lines → `TextReflow.paragraphs`) |
| `list` | list cases |

Options: `--only P01,M04` · `--area math` · `--render` (force re-render) · `--density 1` (force
every case to a 1× capture; writes `*-forced-1x.*`) · `--livetext` (also score macOS Live Text —
VisionKit `ImageAnalyzer` transcript — on the same image) · `--rawvision` (also score Vision's own
observations in Vision's order, one per line, with no TextReflow) · `--out DIR`.

Full review run: `./.build/debug/ocr-bench run --livetext --rawvision` (≈1 min, light load).

## Outputs (`out/`)

- `images/<ID>.png` — the exact image fed to Vision (1× cases are already downscaled).
- `results.txt` — per case: PASS/FAIL, CER, glyph CER, expected vs actual (tabs shown as `⇥`), plus the
  Live Text / raw-Vision baselines when enabled.
- `results.json` — same, machine-readable. `summary.md` — per-area table.

## Scoring

- **Normalization** before comparing (`Scoring.swift`): fold typographic look-alikes a person would
  type either way (− → -, ’‘ → ', “” → ", ′ → ', NBSP → space); strip trailing whitespace per line;
  drop blank lines except in code cases (`keepBlankLines`); in `ignoreSpaces` mode (math) ASCII spaces
  are ignored but newlines and tabs still count.
- **PASS** = normalized clipboard equals one of the case's accepted variants (first = canonical).
- **CER** (character error rate) = Levenshtein(actual, expected) ÷ len(expected), best variant.
- **Glyph CER** = the same with *all* whitespace removed — isolates character recognition from
  layout (line breaks/tabs/indent), though the order of characters still counts.
- Expected-empty cases (`expected: []`) pass only when the result is `.none` ("No text found").

## Ground-truth conventions (what "a careful human would retype")

Paragraph = one line; headings on their own line; list markers kept, nested levels indented (tab or
2/4 spaces accepted); code line-per-line with its indentation and blank lines (spaces, tabs accepted);
table rows one per line with cells separated by **tabs**; multi-column text in reading order (column
by column, a paragraph that flows across the column break joined); math as readable Unicode per the
owner's decision (`x²`, `aₙ`, `(a + b)/2`, `√(x + 1)`, `∫₀¹ x² dx`, `∑ᵢ₌₁ⁿ`, `^(…)` only where
Unicode has no glyph, e.g. `e^(iπ)`); matrices accept `[1 2; 3 4]`, `[[1, 2], [3, 4]]`, `(1 2; 3 4)`.

## Adding a case

Append a `Case(...)` to the right array in `Sources/ocr-bench/Cases.swift`:
`id`, `area`, `desc`, `density` (2 = Retina, 1 = external monitor), `width` (points), `fit`
(tight selection around a formula), `css`, `html` (the snippet inside `#cap`, the simulated
selection; MathML renders natively; `{{QR:payload}}` becomes a locally generated QR image),
`expected` (accepted variants; helpers `indentVariants`, `codeVariants`, `tabOrSpace`), `mode`,
`keepBlankLines`. Then `swift build`, `./.build/debug/ocr-bench render --only NEWID`, **look at
`out/images/NEWID.png`** before trusting it, then `run`.

## How rendering works (no windows in front of the user)

`Renderer.swift` puts a `WKWebView` in a borderless window at (-30000, -30000) at desktop level that
is **never ordered in** (no `orderFront`, no activation; accessory policy), loads the HTML string with
all network navigation cancelled, waits for `document.fonts.ready`, and snapshots the `#cap` element
at the window's 2× backing scale. 1× cases are area-averaged down to 1×. Math uses STIX Two Math.

## Tools (`tools/`, compile with `swiftc -O tools/X.swift -o X`, run from this directory)

- `evidence.swift` — `./evidence out.jpg M04 T01 …` composes image + expected + actual + Live Text
  panels (needs a `run --livetext` first).
- `sheet.swift` — `./sheet sheet.png 1000 out/images/M*.png` contact sheet for eyeballing renders.
- `docprobe.swift` — `./docprobe T01 T03 Y01 …` runs macOS 26 `RecognizeDocumentsRequest` (Vision's
  document-structure API: tables/rows/cells, lists, paragraphs) on corpus images.
