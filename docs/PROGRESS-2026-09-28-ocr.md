# Capture Text (OCR) review + fixes: progress and handoff (2026-09-28)

**Read this first if you are picking this work up.** It is written for a fresh session with no memory
of the one that produced it.

## Latest status (session 2, overnight 2026-09-28 → 29) — read this first

The owner asked to keep working overnight and then run a fresh independent reviewer. Progress so far
(each item committed on `ocr-structure-math`; newest baseline `tools/ocr-bench/baselines/2026-09-29-alignment.json`):

- **Character↔glyph alignment** (`ScriptRecovery.alignment`, a small dynamic program): Vision's characters
  are assigned to glyphs by cost instead of requiring one character per glyph. A full-size glyph takes 1
  character, 2–3 when it is that wide (touching italics `2x`), 0 when Vision dropped it; a script glyph 1
  (0 = dropped, re-read); a stacked fraction any number. Costs: width vs the median letter width; shape
  class (bar = `=`/`−`, speck = `.`/`,`); height class (ascender/capital letters on x-height glyphs and the
  reverse, descender mismatch; digits neutral because of old-style figures); Vision's spaces must fall on
  real gaps; a script never takes a character right after a space. `glyphTexts` builds one *slot* per
  character on its glyph and runs the old repairs on slots.
- Fixed with it: H10 `3/10, … 1 − 3/10 = 7/10` (fractions inside a sentence), H13 `2x³ − 3x² − 12x + 5`
  (plus a re-read correcting a digit Vision read for the letter just before a script: `322` → `3x²`),
  H14 footnotes `¹ ²`, H18 `19th`.
- θ: a glyph with two holes stacked vertically on a line containing sin/cos/tan… (`InkMap.holes`);
  ∫: a stroke > 2.2× cap height read `/`/`J`/`S` on a line with `dx`; `log` look-alikes (`10g`, `l0g`) before
  a subscript or `(`; ordinals (`3rd`, `19th`) stay plain; ready-made superscripts (`™`, `°`) kept; ink of
  other Vision boxes on the same row is excluded unless that box is a short raised exponent; an
  apostrophe is never a script's base; the old-style-digit refusal applies only inside numbers (`log₂8` ok).
- Later the same night (each committed, baselines `2026-09-29-*.json`): shape repairs (prime `′`, `|`,
  `Δ`, raised `⁺`/`⁻` charges, colon/bullet shape classes); code repairs (monospace spacing rebuilt from
  pixel cells in `ScriptRecovery.monospaceSpacing`, bracket balancing / file extensions / hex ids / triple
  quotes in `TextReflow.cleanedCode`, lone `{` `}` `},` lines recovered from loose ink in
  `TextRecognizer.bracketLines`); and **`DisplayMath.swift`** — display equations rebuilt from pixels
  (axis from the `=`, main-row atoms, fractions, `∫`/`∑` told by shape with their limits, `lim`/`max`/`min`
  with the limit under them; only used where `MathLayout` can't: an operator, a limit, or a numerator Vision
  boxed with its row).
- Numbers after DisplayMath: existing 44/66 (CER 0.033), held-out 9/35 (CER 0.113), no-harm 3/6.
  CaptureKit tests 162/162.
- Tracing: temporary `// TRACE` lines (see "Test harness" below) — none are committed.

## What this is

**Capture Text** is the app's OCR (optical character recognition) feature, bound to ⌘⇧7. The user drags a
screen region and the recognized text goes to the clipboard. It uses Apple's on-device **Vision**
framework (`VNRecognizeTextRequest`). No cloud OCR is ever allowed (project hard constraint).

**Owner request (2026-09-28):**
1. Have an independent reviewer test Capture Text on all kinds of content, especially **math**, plus
   prose, lists, code, tables and multi-column layouts.
2. Score it 1–10 on the owner's scale (8–10 near-perfect, 4–7 good with noticeable issues, 1–3 not
   up to standard).
3. Fix what the reviewer finds.

The reviewer's test windows must never appear in front of the owner's windows. The harness renders
offscreen and never orders a window in.

**Owner decision: math pastes as readable Unicode, not LaTeX.** Examples: `x² + y² = z²`, `xᵢ`,
`(a + b)/2`, `√(x + 1)`, `∫₀¹ f(x) dx`. `^(…)` / `_(…)` are used only where Unicode has no glyph
(`e^(iπ)`).

**Pending owner decision (ask before building):** bundle an on-device math-recognition model.
Vision cannot read π θ ∑ ∫ ∀ ε, limits or matrices, and no amount of post-processing fixes that.
It is a big feature, so it needs a short plan and the owner's OK first. The owner has not been asked yet.

## Where the code is

- **Branch `ocr-structure-math`**, one commit on top of `main` (`2affdef`, v3.0.0). It is not merged,
  tagged or pushed.
- CaptureKit unit tests: 161/161 pass (`swift run --package-path Packages/CaptureKit CaptureKitTests`).
- The app builds (`swift build` at the repo root).
- The Windows port's OCR (`windows-port` branch) was **not** touched.

## Timeline and scores

| Stage | Existing 66 cases | Held-out 35 (`H*`) | No-harm 6 (`N*`) | Review score |
|---|---|---|---|---|
| Before any work | 10/66, CER 0.27 | — | — | **3/10** (`docs/reviews/2026-09-28-ocr-review.md`) |
| After first fix round (re-review) | 36/66, CER 0.058 | 2/35, CER 0.177 | 2/6, CER 0.014 | **4/10** (`docs/reviews/2026-09-28-ocr-rereview.md`) |
| End of day (this commit) | 36/66, CER 0.061 | 4/35, CER 0.161 | 3/6, CER 0.011 | not re-reviewed yet |

CER = character error rate: edit distance ÷ expected length, where 0 = perfect.

- The **held-out** cases (`HeldOutCases.swift`, ids `H01`–`H35`) were written by the re-reviewer. I did
  not tune on them. Their job is to measure generalization.
- The **no-harm** cases (`N01`–`N06`) are plain text that must come out untouched.
- The re-review's main complaint was that the math layer **damaged text it wasn't tuned on**:
  `−2.1%` → `-2.1⁰/o`, `5,140` → `5,¹40`, `the 3rd of March.` → `the 3ʳᵈ/1_OfMarch.`, JSON `"node --test"`
  → `"T_(IO)de --testⁱr`.
- All of those are fixed now: `H24` and `N04` pass, and `H18`, `H23` and `H25` no longer show damage.
  See "What changed after the re-review" below.

Diff of end of day against the re-review (`python3 tools/ocr-bench/diff.py tools/ocr-bench/baselines/2026-09-28-rereview.json`):
12 cases are better and 3 are worse.
- `H10` only *looks* worse. Its old output was garbage (`13/1037/103`); it now keeps Vision's own read
  (`1-3=3`).
- **`M17` is a real regression:** `log₂8` became `10g,8`.
- **`M12` is a real regression:** a matrix line now joins the next line.

## Test harness: `tools/ocr-bench/`

This SwiftPM executable renders HTML/MathML cases offscreen in a `WKWebView` that is never ordered in.
It runs the app's real `TextRecognizer.recognize` on each image and scores the clipboard string.
See `tools/ocr-bench/README.md` for the full reference.

```sh
tools/ocr-bench/run.sh                    # build + all 107 cases (~3 min); prints failing ids + per-area table
python3 tools/ocr-bench/summarize.py      # existing / held-out / no-harm split
python3 tools/ocr-bench/summarize.py M17 H13   # expected vs actual for given ids
python3 tools/ocr-bench/diff.py tools/ocr-bench/baselines/2026-09-28-end-of-day.json --show   # what changed vs a baseline
tools/ocr-bench/.build/debug/ocr-bench run --only M17     # one case (results.json then holds only it!)
tools/ocr-bench/.build/debug/ocr-bench dump M17           # raw Vision boxes/candidates/confidences
```

- **Always diff against a baseline after a change.** Aggregate pass counts hide regressions: a fix can
  pass 2 new cases and quietly break 2 others. Today's M21 and M17 regressions were found this way.
- **`run --only` overwrites `out/results.json`.** Run the full corpus before diffing.
- **Baselines** are in `tools/ocr-bench/baselines/`: `2026-09-28-rereview.json` and
  `2026-09-28-end-of-day.json`. Save a new one with `cp tools/ocr-bench/out/results.json tools/ocr-bench/baselines/<name>.json`.
- **Tracing technique:** there are no debug prints in the code. To trace, add temporary
  `if ProcessInfo.processInfo.environment["OCR_TRACE"] != nil { print(...) } // TRACE` lines, then run
  `OCR_TRACE=1 tools/ocr-bench/.build/debug/ocr-bench run --only ID`, and remove them before committing
  with `sed -i '' '/\/\/ TRACE$/d' <files>`. The useful trace points were:
  - `TextRecognizer.recognize`: after `recovered` is computed, print the confidence, `lines[i].text`
    and `recovered`.
  - `TextRecognizer.recognize`: inside the shaky-read closure, print each re-read's text and confidence.
  - `ScriptRecovery.recover`: after `segment(...)`, print each word with its glyph count. Also, before
    `glyphTexts`, print each group's glyphs as `kind`, `F` (fraction), `S` (structure) and `@minX-maxX`.
- New Swift files in CaptureKit need `Packages/CaptureKit/Package.swift` touched before SwiftPM sees
  them. `run.sh` does this.
- The **heavy-job rule** applies (owner's machine): never run several corpus runs at once. One run is
  light (~3 min).

## Pipeline (all in `Packages/CaptureKit/Sources/CaptureKit/`)

1. **`TextRecognizer.recognize`** runs Vision (accurate, language correction on) plus QR detection.
   `reflowLines` converts boxes to top-left normalized coordinates and maps homoglyphs. For each line:
   - `ScriptRecovery.recover` rebuilds super/subscripts and symbols from the pixels. The result goes
     into `Line.recovered`; `Line.text` (Vision's read) stays untouched because layout and code
     detection use it.
   - **Shaky lines** (Vision confidence < 0.9) first try `recover(confident: false)`. That result is
     kept only if every re-read Vision did for it had confidence ≥ 0.9. Otherwise the normal (sure)
     path runs. This fixes `2H₂ + O₂ → 2H₂O` (first read `21120`, confidence 0.5). The damage cases
     all had confidence 1.00, so they stay on the strict path.
   - A short line that is an exponent Vision boxed separately gets absorbed.
   - ` x ` between numbers → ` × `.
   - If `TextReflow.containsCode`, a second Vision pass with correction **off** fills `Line.rawText`
     (matched by box IoU, intersection over union).
2. **`TextReflow.paragraphs(lines, imageSize:, ruleLength:)`** turns lines into clipboard paragraphs:
   - Segments → stacked fractions (`MathLayout.swift`) → detached exponents → line-number gutter drop
     → grids (tables / annotated rows) → code vs prose runs → paragraphs, list levels, and joins across
     columns.
   - **Invariants:** keep Vision's observation order (it is column-aware reading order; never re-sort
     by y); all geometry in pixels; same-row fragments join left to right. Touching fragments join
     without a space only at punctuation.
3. **`ScriptRecovery.swift`** (+ `InkMap.swift`: black/white split by Otsu's method — the threshold that best separates the
   two brightness groups — then 8-connected blobs of ink):
   - Blobs → glyphs (stacked pieces merge; a radical stays a container; inline fractions detected).
   - Cap height and baseline come from full-size glyphs. Each glyph is classified normal / sup / sub.
   - Words are segmented at the widest gaps. If that doesn't line up, the whole line becomes one group.
   - **`glyphTexts` works per word and all-or-nothing** (nil = keep Vision's word):
     - A **space-alignment check** runs in the one-to-one path: Vision's spaces must fall on real word
       gaps. If one falls inside a word, a merged glyph and a dropped glyph cancelled out and the
       mapping is shifted.
     - A **speck rule**: a tiny glyph on the baseline read as a letter is `,` or `.`.
     - Scripts demote punctuation.
     - **Misread detection** re-reads a straightened copy of the word. On a sure line only its
       scripts are taken; Vision's full-size letters stay.
     - Symbol repairs: `√(`, `±`, `≠`, and chemistry `0` → `O`.
     - **The `isFaithful` guard** (below).
     - Inline fractions are rebuilt via `rereadBlobs`, with a typeset `a = ` prefix because Vision
       won't read a lone glyph.
   - **`isFaithful`** is the no-harm guard:
     - A rewrite may only add scripts and known repairs. Every full-size glyph must still be Vision's
       character.
     - `same(out, read)` is **directional**: lowercase only `CKOPSUVWXZ`, `0` → `O`, `+`/`‡` → `±`/`≠`.
     - A script digit followed by a full-size digit is rejected (Georgia's old-style `1` in `5,140`).
     - Skipping `=<>≤≥` is rejected.
     - On a shaky line, the full-size glyphs may differ from Vision's read by at most 75% of its length.
4. **`MathLayout.swift`**: stacked fractions need a bar ≈ the fraction's width (longest horizontal
   ink run) *and* something beside it on the bar's line. It also handles detached exponents.
5. **`Homoglyphs.swift`**: Cyrillic/Greek look-alikes → Latin unless the user reads those scripts.
6. **`RecognitionResult.swift`**: a QR payload wins only if the code covers ≥ 20% of the selection.
   Otherwise it is appended to the text.

## What changed after the re-review (this evening)

- Added the faithfulness guard and the separate `recovered` field, and made the code signals stricter.
  Chemistry and log sentences are no longer classified as code.
- Made `same()` directional.
- Added the shaky-line path, driven by Vision's own confidence. It restored M13.
- On a sure line, a re-read only contributes scripts, so `A = πr²` gives `Tr²` rather than rejecting
  the whole word.
- Added the space-alignment check (fixes H10's `13/1037/103` garbage) and the speck rule.
- A sup/sub `=` counts as a misread (fixes H07 `m s=2` → `m s⁻²`).
- Fraction glyphs count toward the per-word glyph tolerance.
- Touching same-row fragments keep their space unless there is punctuation at the join (fixes
  `3rdof`).
- Tried and reverted: skipping inline fractions when counts mismatch broke M21 `(1 + r/n)ⁿᵗ`. The H10
  damage actually came from misalignment.

## Remaining failures, diagnosed

### Caused by our pipeline (fixable)

1. **M17 regression: `log₂ 8` → `10g,8`.** It was `log₂8` at the re-review. The likely cause is
   the directional `same()` or the sure-line "keep Vision's letters" rule: Vision reads `10g,8`, the
   re-read `log28`, and now Vision's `10g` wins. Check the line's confidence with `ocr-bench dump M17`.
   A narrow fix idea: allow `1`/`l` and `0`/`o` when the whole word re-reads as a known function name
   (`log`, `ln`, `lim`, `sin`, `cos`, `tan`).
2. **H13 (a typical IB — International Baccalaureate — exam line): every exponent is lost** in `f(x) = 2x³ − 3x² − 12x + 5`.
   - Italic math letters touch, so `2x` is one blob. Glyph and character counts can't match, so the
     all-or-nothing rule keeps Vision's `2x3-322`.
   - Word segmentation also fails: operator gaps are wider than word gaps.
   - **Proposed fix:** re-read *runs* instead of glyphs. Render the straightened line with each
     normal run and each script run as separate pieces (or re-read each run on its own). Map
     re-read tokens to runs, not characters to glyphs. That makes it robust to merged glyphs.
   - This is the highest-value remaining math fix. M19 `3x?` / `2X` is likely the same problem.
3. **H10: inline fractions inside a sentence** (`3/10,` read as `To`).
   - Vision's per-word boxes (`VNRecognizedText.boundingBox(for:)`) were measured: about ±12 px off
     for words, and useless for math tokens (the whole range comes back). They can't anchor segmentation.
   - Idea: anchor on operator characters (`−`, `=`) against bar-shaped glyphs and map the segments
     between them.
4. **H14: footnote `¹` read as `'`.** The apostrophe demotion rule (`width < 0.25 cap`) also catches
   a narrow superscript `1`. Try `width < 0.25 cap && height < 0.55 cap`.
5. **H25: a header cell (`2023`) is missing.** Undiagnosed. Check `dump H25` to see whether Vision or
   the grid dropped it.
6. **H27 / T07: single-letter table cells** (`ρ`, `v`, `p`) come out empty. Vision skips lone glyphs.
   Idea: re-read the empty cells of a grid with the `a = ` prefix trick.
7. **H30** (sidebar + settings pane mis-gridded), **H31** (figure caption placed last), **H15** (two
   paragraphs merged: with only 2 lines there is no pitch reference), **M12** (matrix line joins).
8. **H06: no output at all.** Vision with correction on returns 0 observations for `|v| = √(v₁² + …)`.
   Consider retrying with correction off when the first pass finds nothing (it returns a 0.3-confidence
   read).
9. **H08: chemistry charges** (`Fe³⁺` read `Fe3t`). Be careful: tuning on held-out cases inflates the
   score.

### Vision limits (need the math model or a dictionary, owner decision)

- Letters and symbols Vision can't read: π θ Δ ∑ ∫ ∀ ε ∈ ℝ ⌘ ⌥ ⇧ (H01, H03, H04, H11, H12, H29, M03,
  M08–M11, M16, M17 θ, M20).
- Big-operator limits, `lim` with `h→0` below, matrices.
- Missing single-brace lines in JSON (H23).
- `Ana lonescu` / `loana` (I→l), `Ș`/`Ț` → `S`/`T` (Romanian isn't a Vision language), em dash → `-`.
- `%%` → `88`, lone `}` read as `i`, `$HOME` → `$HoME`.

## Next steps (in order)

1. Fix the M17 regression. Rerun and diff against the end-of-day baseline.
2. Add unit tests for today's logic:
   - `ScriptRecovery.isFaithful`: the old-style-digit refusal, the equal-count normal mismatch, the
     subsequence with skipped `=`, the directional `same` (`O` from `0` allowed, `0` from `O` refused),
     and the shaky-line distance rule.
   - `ScriptRecovery.distance`.
   - The TextReflow punctuation-only tight join (`3rd` + `of March.` keeps its space; `printf("%d\n"` +
     `, *p);` doesn't).
   - The recognizer's shaky-line path, using a rendered image test like
     `superscriptsAndSubscriptsComeFromThePixels` in `TextRecognizerTests.swift`.
3. The H13 run-level re-read (step 2 of the list above). It is the biggest remaining math win.
4. The smaller pipeline items (H14, H25, H27, H06, H30/H31).
5. **Fresh third review.** Launch a new independent reviewer with the brief of
   `docs/reviews/2026-09-28-ocr-rereview.md`. It must write **new** held-out cases, because the
   `H*` set has now been looked at while fixing.
6. Ask the owner about the bundled math model. Then update CHANGELOG, root `CLAUDE.md` and this file,
   merge `ocr-structure-math` into `main`, and tag if the owner wants a release.
