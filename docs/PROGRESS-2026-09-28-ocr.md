# Capture Text (OCR) review + fixes: progress and handoff (2026-09-28)

**Read this first if you are picking this work up.** It is written for a fresh session with no memory
of the one that produced it.

## Latest status (session 2, overnight 2026-09-28 → 29) — read this first

The owner asked to keep working overnight, then run a fresh independent reviewer. Everything below is
committed on branch `ocr-structure-math` (not merged, not tagged). **Newest corpus baseline:
`tools/ocr-bench/baselines/2026-09-29-icons.json`.**

**Numbers now** (`tools/ocr-bench/run.sh`, then `python3 tools/ocr-bench/summarize.py`):
existing **54/66** (CER 0.020) · held-out **19/35** (CER 0.085) · no-harm **5/7** (CER 0.010) ·
CaptureKit unit tests **181/181**. At the start of the night: 41/66 · 8/35 · 3/6. CER = character error
rate (edit distance ÷ expected length). Median recognition time in the debug bench ≈ 360 ms (was ≈ 290).

What was added, in pipeline order (all in `Packages/CaptureKit/Sources/CaptureKit/`):

- **Character↔glyph alignment** (`ScriptRecovery.alignment`, a small dynamic program): Vision's characters
  are assigned to glyphs by cost instead of one character per glyph — a wide full-size glyph may take
  2–3 characters (touching italics `2x`), a dropped glyph 0; costs from width, shape class (bar, speck),
  height class, and Vision's spaces having to fall on real gaps. `glyphTexts` works on one *slot* per character.
- **Touching scripts** (`ScriptRecovery.splitRaisedTails`): at low resolution `x²` is one blob; a run of
  columns on its right that stays half a capital off the baseline and rises ≥ 0.45 cap above the rest is
  cut off. Cap and baseline are measured *without* that glyph (alone it looks like the tallest letter).
- **Shape repairs** in `glyphTexts`: prime `′`, `|`, `Δ` (a filled base), `θ` (two stacked holes, trig
  lines only), `∫` (tall stroke on a line with `dx`), `π` (read `T`, but has two legs — `isPi`), raised
  `⁺`/`⁻` charges, `log` look-alikes (`10g₂8`) and `ln` read as `In` before its argument (`repairingLog`).
- **Dashes, dots, separators, markers** (`ScriptRecovery.dashesAndDots`): em/en dash from width, `·` from
  size, `3.760` ↔ `3,760` from the separator's shape (a comma has a tail; the baseline is useless with
  old-style figures), en-dash list markers, checkboxes Vision reads as `•` (`☐` hollow, `☑` ticked,
  a solid UI box dropped — `checkbox`), and a leading icon (taller than the text's capitals, `isIcon`) dropped.
- **Missing full stop** (`ScriptRecovery.missingFullStop`): a round baseline speck after a line ending in
  a quote, bracket or digit (`the teachers’.`, `= 7/10.`).
- **Table cells Vision didn't box** (`TextRecognizer.cellLines`): only when some row holds two lines;
  loose ink on a text row, a cell's gap from its neighbours, lined up with a line in another row; read
  with the `a = ` prefix at its real size and baseline (`ScriptRecovery.readInk(…, baseline:)`), `V`→`v`
  by height, italic `y` without a tail → `v`. Fixed `2023` header (H25), `v` (T07), `p`/`v` (H27).
- **Display math** (`DisplayMath.swift`): equations rebuilt from pixels — axis from the `=`, fractions,
  `∫`/`∑` by shape with limits, `lim`/`max`/`min` with the limit under them, matrices between tall
  brackets (`[1 2; 3 4]`). Only used where `MathLayout` can't.
- **Math line tidying** (`MathLayout.swift`, applied in `TextReflow.prose` to lines `isMath` accepts):
  `repairedMathSymbols` (`A n B` → `A ∩ B`, `A U B` → `A ∪ B`, `x E R` → `x ∈ ℝ`, a stray `.` after `=`,
  a space after a comma between terms) then `spacedOperators` (`F= ma` → `F = ma`, binary `+ - × ÷`
  spaced, unary signs and hyphenated words left alone).
- **Code** (`TextReflow.cleanedCode`, `ScriptRecovery.monospaceSpacing`, `TextRecognizer.bracketLines`):
  spaces rebuilt from monospace cells, bracket balancing, file extensions, hex ids, triple quotes, lone
  `{` `}` `},` lines from loose ink.
- **Layout** (`TextReflow`): compounds broken at a line-end hyphen keep it unless the system word list
  (`WordList.swift`, `/usr/share/dict/words` + stemming) knows the joined word; two lines alone more than
  4.8 character widths apart are two paragraphs; a caption Vision lists after the next column goes back
  under its figure (`columnOrdered`); a sidebar beside a table (short items at the layout's edge, mostly
  not lined up with its rows) is kept out of the grid (`sidebar`), and a column no wider than two words is
  a list of labels, not wrapped text.
- New no-harm case **N07** (`tools/ocr-bench/Sources/ocr-bench/HeldOutCases.swift`): icon sidebar —
  icons must not come out as letters.
- Tracing: temporary `// TRACE` lines inserted by a scratch script and removed before every commit —
  none are committed.

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

## Remaining failures, diagnosed (as of `2026-09-29-icons.json`)

### Caused by our pipeline (fixable)

1. **Merged italic letters** that aren't scripts: `2X` for `2x` (M19), `f(x)` loses its prime when the
   prime touches the italic `f` (H13). The alignment can give a wide glyph two characters, but case and
   prime repairs work per glyph.
2. **Nested scripts**: `e^(−x²)` comes out `e⁻ˣ²` (H09 line 1), and line 2 isn't recovered at all.
3. **A full stop after a stacked fraction on a prose line** (M18 `…/(x − 3).`): `missingFullStop` only
   looks right of Vision's own box, and the fraction sits between.
4. **`log₂32` → `log232`** (H02): the subscript is found but the rewrite is refused by the no-harm guard.
5. **`2 sin² 0`** for `2sin²θ` (H03 line 2): the last θ isn't recognized (θ needs two holes; this one is
   read as `0` in a word the alignment splits differently).
6. **`e^(In)`** for `e^(iπ)` (M16): a superscript `π` read as `n` — `isPi` only runs on `T`, deliberately
   (an `n` has two legs too).
7. **H15** `3x` for `3×` (the glyph is a real ×; Vision reads x), `B0. 12` (Vision's correction inserts a space).
8. **H35** (icons only) returns `-O-` — Vision reads a crosshair icon as text; `isIcon` needs other text
   on the line to measure against.
9. **M06** `2O₁` for `2a₁`, `n/2(` spacing.

### Vision limits (need the math model or a dictionary — owner decision)

- Symbols Vision can't read at all: ∑ ∀ ε ⌘ ⌥ ⇧ Greek in general (H01, H06 and M10 return nothing or
  junk, H29 `⌘Z` → `HZ`), cube roots (M07).
- `Ana lonescu` / `loana` (I→l), `Ș`/`Ț` → `S`/`T` (Romanian isn't a Vision language), `A0` → `AO`
  (N03, H16), `%%` → `88` (N05), `%d` → `d` (C06), `$HOME` → `$HoME` (C08), `SI` → `Si` (T07), a
  misspelling (P05), `Q` → `2` (H27).
- Code odds and ends: H20/H22/H23/C03 are one or two characters off (a brace read as `(`, etc.).

## Next steps (in order)

1. **Fresh third review** (running/ran on 2026-09-29): a new independent reviewer with the brief of
   `docs/reviews/2026-09-28-ocr-rereview.md`, writing **new** held-out cases (the `H*` set has been looked
   at while fixing). Its report: `docs/reviews/2026-09-29-ocr-review.md`.
2. Fix what it finds, diffing every change against the newest baseline (`python3 tools/ocr-bench/diff.py
   baselines/<newest>.json`).
3. Ask the owner about a bundled on-device math model for what Vision can't read (∑ ε Greek, big
   operators). Nothing has been decided; no model is in the repo.
4. Merge `ocr-structure-math` into `main`, update CHANGELOG (an "Unreleased" entry exists) and tag if the
   owner wants a release. The Windows port's OCR was **not** updated.
