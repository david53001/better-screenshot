# Capture Text (OCR) review — 2026-09-29

**Overall: 4/10** — "Good, with noticeable issues", at the low end of that band. On 44 new cases
written for this review, the pipeline passes **14/44** (mean CER 0.050). macOS Live Text passes 8/44
(0.137) and raw Vision 7/44 (0.192). So it clearly beats Apple's own copy-text at structure:
- tables come out as tab-separated grids,
- code keeps its indentation, blank lines and lone braces,
- wrapped paragraphs rejoin,
- two-column pages come out in reading order.

On the sets it was tuned on it passes 78/108. That gap (72% on tuned cases, 32% on unseen ones) is
the main finding: many fixes match the exact shape of the cases they were written for. Three things
keep it below 5:
- **Math: 0/11.** 7 of the 11 new formulas come out with their meaning changed: a root or `∫` is
  dropped, `π` becomes `n`, `≈` becomes `=`, a fraction's numerator is lost.
- **The rebuilding layer still damages plain text.** 8 of the 33 new non-math cases contain an
  error raw Vision did not make: `p. 42` → `_P. 42`, Romanian `organizează pe` → `organizează_Pe`,
  `50%` → `50⁰%`, `Update to v2.11.0 from` → `Updateto v2.11.0from`, a lost comma, and short lines
  glued together.
- **Tables:** tables with a narrow column or an empty cell put values in the wrong column.

This is real progress since the 2026-09-28 re-review. On cases it hadn't seen, the pipeline then
passed 2/35 at CER 0.177; now it passes 14/44 at CER 0.050. The owner still can't paste without
proofreading, though.

**Standard:** the clipboard holds what a careful human would retype on the first try, at least as
good as CleanShot X / macOS Live Text (see Calibration) · **Method:** 44 new cases (ground truth
written before any output was seen) + the existing 66 + the 42 earlier held-out/no-harm cases, all
also scored with Live Text and raw Vision; code reading for root causes; CaptureKit unit tests ·
**Reviewer:** independent subagent (did not build the feature)

## Calibration

- **What it is:** the user drags a screen region. The pixels go to Apple **Vision**
  (`VNRecognizeTextRequest`: on-device OCR, "accurate" level, language correction on, languages
  `en-US` + `ro-RO` on this machine) plus QR detection. The recognized lines are rebuilt into text
  and put on the clipboard. Entry point: `TextRecognizer.recognize(in:pointWidth:)` in
  `Packages/CaptureKit/Sources/CaptureKit/TextRecognizer.swift`. The rebuilding code is in the same
  folder: `TextReflow.swift`, `MathLayout.swift`, `DisplayMath.swift`, `ScriptRecovery.swift`,
  `InkMap.swift`, `Homoglyphs.swift`, `WordList.swift`.
- **Audience:** the owner (an IB — International Baccalaureate — high-school student) and general
  users. They capture slides, PDFs/textbooks, worksheets and **math**, web articles, code, tables, UI
  screenshots and video frames. They paste into Docs, Notes, AI chats, code editors and spreadsheets.
- **Maturity:** a personal tool with tagged releases, so it is expected to feel finished.
  **Constraint:** fully local, never any cloud OCR.
- **Math format (owner decision):** readable Unicode, not LaTeX — `x² + y² = z²`, `xᵢ`, `(a + b)/2`,
  `√(x + 1)`, `∫₀¹ f(x) dx`, `∑ᵢ₌₁ⁿ i`, Greek, `≤ ≥ ≠ ± × ÷ → ∞ ∈`. Use `^(…)`/`_(…)` only where
  Unicode has no glyph (e.g. `e^(iπ)`, `e^(−x²)`). Flattening `x²` → `x2` is **wrong**.
- **A 10:** exact characters; paragraphs rebuilt; headings on their own line; lists one item per line
  with markers and nesting; code line-per-line with indentation; tables one row per line with
  **tab**-separated cells; multi-column text in reading order; math as readable Unicode. At least as
  good as CleanShot X and macOS Live Text.
- **Anchors:**
  - **3** = a common input (textbook equation, simple table, two-column page) comes out scrambled or
    meaning-changed.
  - **6** = prose, lists and code paste correctly; math and tables lose structure that can be fixed by
    hand in under a minute.
  - **9** = everything pastes correctly first try, apart from rare glyph-level misreads Live Text also
    makes.
- **Severities:**
  - **High:** the meaning changes, content is lost or scrambled, or the user must retype.
  - **Medium:** noticeable cleanup.
  - **Low:** rare or cosmetic.

  An area with a High issue can't score 8+.
- **Scale (the owner's):**
  - **8–10:** basically perfect.
  - **4–7:** a great app / good code, with noticeable issues.
  - **1–3:** not to our standard.
- **Terms:**
  - **CER** (character error rate) = edit distance ÷ expected length; 0 = perfect.
  - **Glyph CER** = the same with all whitespace removed. It isolates character recognition from
    layout.
  - **Pass** = the normalized clipboard exactly equals an accepted ground truth. Normalization folds
    `−`/`-`, curly/straight quotes and NBSP (non-breaking space); math cases ignore ASCII spaces.
  - **Raw Vision** = Vision's own lines in its order, with no rebuilding.
  - **Live Text** = macOS's built-in copy-text-from-image (VisionKit `ImageAnalyzer`) on the same
    image.
  - **Pipeline-introduced** = an error that is not in raw Vision's output (our code added it).

## Scoreboard

| Area | Score | New cases pass · CER | Tuned sets pass · CER | Verdict (one line) |
|---|---|---|---|---|
| Prose | **5/10** | 1/6 · 0.010 | 7/11 · 0.003 | Paragraphs, headings, soft hyphens and footnote markers are right. Ordinary words are corrupted (`_Pe`, `_P.`), and dashes and Romanian `Ș` are misread |
| Lists | **7/10** | 1/2 (+V34 1/1) · 0.002 | 7/7 · 0.000 | 1./a./i. nesting and wrapped `<ol>` items are right. Only glyph-level dash issues |
| Code | **6/10** | 2/5 · 0.019 | 6/12 · 0.006 | Structure is excellent (Allman braces, two blank lines, 1× Python, JSON). A zsh session is glued; backticks come out as quotes |
| Tables | **5/10** | 1/5 · 0.019 | 8/11 · 0.011 | Far ahead of Live Text. A narrow column or empty cell shifts values into the wrong column (V29, V30) |
| Math | **3/10** | 0/11 · 0.166 | 23/35 · 0.085 | ∑ with limits and simple scripts work. 7/11 new formulas change meaning (root, ∫, π, ≈, numerator lost) |
| Layout & reading order | **7/10** | 3/4 · 0.003 | 12/13 · 0.010 | Two-column page, form, notification and nav row are right. Short separate lines get glued (V35, V37) |
| Robustness | **5/10** | 1/4 · 0.012 | 10/12 · 0.084 | Vision read all 4 hard images perfectly (raw 4/4). The pipeline then broke 3 of them |
| No-harm | **4/10** | 5/7 · 0.008 (8 of 33 non-math new cases damaged) | 5/7 · 0.010 | Dates, prices, ISBNs, arrows and `x` are safe. Prose taken for code loses its spaces; the `%` ring and descender `p` are turned into scripts |
| Pipeline code quality | **4/10** | 181/181 unit tests pass | — | Readable and commented, but rules are fitted to seen cases, guards have holes, and 1,258-line ScriptRecovery has ~90 magic ratios |
| **Overall** | **4/10** | **14/44 · 0.050** | **78/108 · 0.041** | Big structural lead over Live Text; math and silent corruption keep it from a 5–6 |

(The "new cases" column counts V01–V37 in their own area; no-harm V38–V44 are counted only in the
No-harm row. V34 is a Comic Sans list filed under robustness.)

## Numbers

All numbers come from one run of `ocr-bench run --livetext --rawvision` (debug build) over all 152
cases. Results are in `tools/ocr-bench/out/review3-full/results.json`; the new-set-only run is in
`tools/ocr-bench/out/review3/`.

| Set | Cases | BetterScreenshot pass · CER | Live Text pass · CER | Raw Vision pass · CER | Ours better / worse than Live Text (by CER) |
|---|---|---|---|---|---|
| **New (V01–V37)** | 37 | **9 · 0.058** | 4 · 0.161 | 4 · 0.227 | 25 / 6 |
| **New no-harm (V38–V44)** | 7 | **5 · 0.008** | 4 · 0.008 | 3 · 0.008 | 2 / 1 |
| **New, all** | 44 | **14 · 0.050** | 8 · 0.137 | 7 · 0.192 | 27 / 7 |
| Existing corpus (tuned) | 66 | 54 · 0.020 | 14 · 0.182 | 5 · 0.237 | 50 / 0 |
| Earlier held-out H01–H35 (tuned since) | 35 | 19 · 0.085 | 0 · 0.201 | 0 · 0.274 | 31 / 2 |
| Earlier no-harm N01–N07 (tuned since) | 7 | 5 · 0.010 | 2 · 0.045 | 2 · 0.070 | 4 / 1 |

**By area, new vs tuned** (pass · CER; Live Text and raw Vision on the same new cases):

| Area | New: ours | New: Live Text | New: raw Vision | Tuned: ours |
|---|---|---|---|---|
| Prose (V12–V17) | 1/6 · 0.010 | 1/6 · 0.009 | 0/6 · 0.017 | 7/11 · 0.003 |
| Lists | 1/2 · 0.002 | 0/2 · 0.040 | 0/2 · 0.037 | 7/7 · 0.000 |
| Code | 2/5 · 0.019 | 0/5 · 0.079 | 0/5 · 0.070 | 6/12 · 0.006 |
| Tables | 1/5 · 0.019 | 0/5 · 0.175 | 0/5 · 0.763 | 8/11 · 0.011 |
| Math | 0/11 · 0.166 | 0/11 · 0.391 | 0/11 · 0.348 | 23/35 · 0.085 |
| Layout | 3/4 · 0.003 | 1/4 · 0.055 | 0/4 · 0.059 | 12/13 · 0.010 |
| Robustness | 1/4 · 0.012 | 2/4 · 0.010 | **4/4 · 0.000** | 10/12 · 0.084 |

**The overfitting signal:**
- Tuned math passes 23/35; new math passes 0/11.
- `∫₀¹ x² dx` (M08) and `∫ x³ dx` (H04) pass, but `∫₁³ (2x + 1) dx` (V05) loses its `∫`.
- The `~/ib-ia $` terminal prompt from H21 passes, but zsh's default `david@MacBook ~ %` (V26) is
  not recognized as a prompt.

**Pipeline-introduced errors on the new set (errors raw Vision did not make):** 9 of 44 cases.
- V13 `p. 42` → `_P. 42`
- V14 `organizează pe` → `organizează_Pe`
- V16 `energy, which` → `energy which`
- V26 two prompt lines glued into one
- V35 footer and address lines glued
- V36 `50%` → `50⁰%`
- V37 `(odd)` and `Revise:` lines glued
- V39 `Update to v2.11.0 from` → `Updateto v2.11.0from`
- V11 Vision's `m1mz` became `mıᵐZ`

Eight of the nine are in text with no math in it.

**Speed** (debug build, as run by the harness): median 374 ms per capture, p90 906 ms, max 2.2 s
(V33, a 7×4 table). Release was not measured — see Method & limits.

## Prose — 5/10

**Works well:**
- Wrapped paragraphs rejoin, and headings stay on their own line (V12, V17, V20).
- A justified, auto-hyphenated narrow column rejoins `electro-`+`magnetic` correctly (V16).
- A footnote marker comes out as `rule.¹`, where Live Text gives `rule.'` (V13).
- An italic paragraph with a spaced em dash is right (V17).
- Live Text returns V12, V17 and V13 as unjoined visual lines; ours joins them.

**Issues:**

| # | Severity | Case | Problem (expected → actual) | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| P1 | **High** (pipeline) | V14, V13 | `organizează pe 15 martie` → `organizează_Pe 15 martie`; `(2019), p. 42.` → `(2019),_P. 42.` | Plain words are corrupted silently. The trigger is a lowercase descender letter after a taller glyph (`ă` with its breve, `)`), which is extremely common in Romanian — the owner's language. Raw Vision and Live Text are both correct. | `ScriptRecovery.classify` (`ScriptRecovery.swift:590-596`) marks a glyph `.sub` when its bottom is below the baseline and its top is lower than the previous glyph's top — exactly what a `p`/`g`/`q`/`y` after `ă` or `)` looks like. The re-read returns `P`, and `script()` (`:1244-1249`) prints `_P` because capital P has no subscript. `isFaithful` (`:1062-1093`) checks only full-size glyphs, so it can't catch this. Fix: (a) a lowered glyph whose top is at x-height is a descender letter, not a subscript; (b) never subscript the first glyph after a space; (c) when Vision is confident, script glyphs must keep Vision's letter too (case-insensitively). |
| P2 | Medium (pipeline) | V16 | `chemical energy, which` → `chemical energy which` | A comma vanishes. Vision's top candidate had it (`dump V16`). | It is lost after Vision, in the per-line rebuild. The likely cause: `y` + `,` merge into one glyph in Hoefler Text, and the glyph↔character alignment drops the comma. Not traced to a line; a missing character should make `recover` return nil. |
| P3 | Low (Vision) | V12, V19 | `—` → `-` / `–`; `…` kept only as `...` | Typographic dashes are flattened. Live Text does the same. | `dashesAndDots` (`ScriptRecovery.swift:264-310`) already measures dash width. V12's em dashes stayed `-`, so check its `g.width >= 0.95 * cap` threshold against Avenir Next's em dash. |
| P4 | Low (Vision) | V14, V33 | `Ștefănescu` → `Ştefănescu`, `Timiș` → `Timiş` (cedilla instead of comma-below) | Wrong Romanian letter (legacy cedilla form); search and spell-check treat it as a different letter. Live Text does the same. | When `ro` is among the recognition languages, map `Ş ş Ţ ţ` → `Ș ș Ț ț`. A one-line table in `Homoglyphs.swift`. |
| P5 | Low (Vision) | V15, V41 | `−3 °C` → `- 3 °C`; `1st` → `Ist`; `H2O` → `H20` | Glyph misreads Live Text also makes. | `Ist`/`H20` could be repaired by rules (digit+`st`; element symbol + digit), but that's optional. |

**Why 5:** paragraph and heading structure is at the "6" anchor or better, ahead of Live Text.
P1 is a High, silent corruption of ordinary words that hits the owner's own language, so the score
drops a point.

## Lists — 7/10

**Works well:**
- V18: a three-level `1.` / `a.` / `i.` outline is correct with tab nesting. Live Text puts
  `i. Scope ii. Limitations` on one line.
- V19: a wrapped `<ol>` step on a dark-blue slide rejoins into one item.
- V34: a Comic Sans numbered list on yellow is perfect.
- Tuned lists pass 7/7.

**Issues:**

| # | Severity | Case | Problem | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| L1 | Low | V19 | `formulas — never` → `formulas – never` (Vision read `-`; the pipeline upgraded it to an en dash, not an em dash) | Cosmetic. | Same as P3. |
| L2 | Medium (cross-cutting) | V37 | short separate lines without markers get glued (see Layout Y1) | A marker-less list (chalkboard, notes) turns into one line. | See Y1. |

**Why 7:** nothing High. Nesting, markers and wraps are right on every list case I wrote. It isn't 8
because the evidence is thin (3 new cases, no checklist) and because the Y1 merge also hits
marker-less lists.

## Code — 6/10

**Works well:**
- V25: C with Allman braces (`{` alone on a line) is rebuilt perfectly. Raw Vision and Live Text
  both drop the lone `{` lines.
- V28: 1× Python keeps both blank lines after the import, the decorator and 8-space nesting.
- V27: JSON in Andale Mono is perfect (the earlier review's H23 class of failure is fixed).
- V24: JavaScript keeps its 2-space structure and `?.`/`??`/`=>`.
- Ours beats Live Text on all 5 new code cases.

**Issues:**

| # | Severity | Case | Problem (expected → actual) | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| K1 | **High** (pipeline) | V26 | zsh session: `david@MacBook ~ % cd ~/Projects/ia` and `david@MacBook ia % ls -1` → one line. Also left: `1s -1`, `analysis. py`, `data. CSV`, `README•md`. Raw Vision had the lines apart, and its no-correction read had `analysis.py`. | Pasted commands are wrong and would fail if run. zsh is the macOS default shell. | The prompt pattern (`TextReflow.swift:529`) accepts `user@host:~$` but not zsh's `user@host dir % ` (a space before the directory). The block isn't classified as code, so the raw re-read and `cleanedCode` never run, and the prose fit test glues lines 1–2. Accept `^[\w.-]+@[\w.-]+ \S+ [%$#] `. More generally, treat a monospaced block with ≥2 prompt-shaped lines as code. |
| K2 | Medium (Vision) | V24 | `` `/api/…/${studentId}/grades` `` → `'/api/…/${studentId}/grades"`; `${res.status}` → `$fres.status}` | JS template literals no longer parse. Live Text makes the same errors. | In `cleanedCode` (`TextReflow.swift:594`): `$f` → `${` when a `}` closes it; mismatched quote pairs around `${…}` → backticks. |
| K3 | Medium (Vision) | V25 | `i++` → `itt` | A C loop no longer compiles. Live Text is the same. | `cleanedCode`: `\b(\w)tt\b` → `$1++` in code blocks. |
| K4 | Low | V26 | `Mean: 12.48  SD: 3.07` → `Mean: 12.48⇥SD: 3.07` | Two spaces became a tab (the line was treated as a two-cell row). | In a monospaced block, rebuild the gap from the character grid instead of tabbing. |

**Why 6:** code structure is the strongest part of the pipeline and meets the "6" anchor ("code
pastes correctly") for editors. The zsh session (K1) is High and reachable by the most ordinary
terminal capture on a Mac, so it doesn't reach 7.

## Tables — 5/10

**Works well:**
- V32, a 1× dark GitHub-style table with zebra rows, is perfect. Live Text gives one cell per line;
  raw Vision gives columns (CER 0.80).
- V31, a borderless IB lab table, and V33, a Wikipedia-style table with a caption: rows and tabs are
  perfect.
- Tuned tables pass 8/11.

**Issues:**

| # | Severity | Case | Problem (expected → actual) | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| T1 | **High** | V29 (1× Google Sheets) | Header `Paper 2⇥IA` → `Paper 2 IA` (two cells merged). Row `Ionescu M.⇥28⇥⇥20` → `Ionescu M.⇥28⇥20` (empty cell dropped, so `20` lands under **Paper 2**). Same merge on the other rows: `41 18`, `45 22`. | Pasted into a spreadsheet, marks go into the wrong column silently. This is the classic "grades from a Sheet" capture. | Column bands come from text x-extents (`columnBands`, `TextReflow.swift:429`). A narrow column (`IA`, 2 characters) close to its neighbour falls inside the adjacency join (`isAdjacent`, `:856`, `sameRowJoinChars`). The grid has visible gridlines: use vertical rules from the ink (`InkMap.longestRun` exists already) as cell boundaries when present. |
| T2 | **High** | V30 (bordered timetable) | `3⇥12:55–13:45⇥Spanish⇥Free⇥Maths HL` → `3⇥12:55–13:45 Spanish⇥⇥Free⇥Maths HL` | Wrong columns again: "Free" moves to Wednesday. | Same root cause as T1. Here the merged `Lunch` cell (spanning 3 columns) also distorts the column bands. Band-building should ignore a cell that overlaps several bands. |
| T3 | Low | V30 | `L⇥12:10–12:50⇥Lunch` → `L⇥12:10–12:50⇥⇥Lunch` | A merged cell is placed under its centre column. Defensible. | — |
| T4 | Medium (Vision) | V31 | `Length / cm ± 0.1` → `Length / cm = 0.1` (both headers) | The uncertainty becomes an equation. Live Text does the same. | `±` repair exists for a `+` with a bar under it; add the "`=` whose top stroke has a vertical through it" shape (`isPlusMinus`, `ScriptRecovery.swift:1125`). |
| T5 | Low (Vision) | V33 | `Iași` → `lași`; `Timiș` → `Timiş` | Glyph level. | P4; plus capital `I` vs `l` from the column's other cells. |

**Why 5:** three of five new tables have correct structure — much better than Live Text, which has
no table output at all. But T1/T2 put values into the wrong column without any sign that something
is off, on two of the most common table sources (a Sheet and a school timetable). By the rules that
is High, so 5, not 6.

## Math — 3/10

**Works well:**
- V06: `∑ᵣ₌₁ⁿ … = n(n + 1)(2n + 1)/6` is rebuilt with limits and a stacked fraction. The only error
  is Vision's `r` → `p`.
- V10 line 1 (`c² = a² + b² − 2abcosC`), V03's `x²`, V02's `dy/dx = 1/xln2` and V05's `[x² + x]³₁`
  are all recovered.
- New-set math CER is 0.166, against 0.39 for Live Text and 0.35 for raw Vision. It is more useful
  than either.

**Issues:**

| # | Severity | Case | Problem (expected → actual) | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| M1 | **High** | V01 | `f⁻¹(x) = 2 + √((x − 5)/3)` → `f(x) = 2 + 1 - (X - S)/3` | The inverse becomes the function; the root becomes `1 -`; `5` becomes `S`. A standard IB inverse-function answer, with its meaning changed. | The radical over a *fraction* isn't found: `assemble` only opens `√(` when Vision read the radical as `V`/`√`/`/` (`ScriptRecovery.swift:463-466`), and here it read `1-`. A radical is a blob enclosing others, so detect it from the ink regardless of what Vision read. |
| M2 | **High** | V07 | `\|a\| = √(2² + (−1)² + 3²) = √14` → `lal = 2² + (-1)² + 3² = √(14)` | The long root is dropped, and `\|a\|` becomes `lal`. Earlier held-out H06 (the same shape) still returns "No text found". | Same radical detection as M1. `\|x\|` → `l x l`: map `l…l` around a single letter to `\|…\|` on math lines. |
| M3 | **High** | V05 | `∫₁³ (2x + 1) dx = [x² + x]₁³ = 10` → `(2x + 1) dx = [x² + x]³₁ = 10` | The integral sign and its limits vanish, and a definite integral turns into an expression. The tuned M08 (`∫₀¹ x² dx`) passes. | `DisplayMath`'s ∫ detection (`DisplayMath.swift:202-217`) is keyed to ink Vision leaves unboxed. Here Vision boxed `3` separately and not the ∫. Check for a tall integral-shaped blob left of the first line in any display formula. |
| M4 | **High** | V10 | `cos C = (a² + b² − c²)/(2ab)` → `COsC = •` ⏎ `2ab` | The numerator is lost; the cosine rule can't be recovered. | `MathLayout` needs a numerator line above the bar. Vision returned nothing for the superscript-dense numerator. Re-read the ink above a detected bar (the `rereadBlobs` trick). |
| M5 | **High** (Vision + missing mapping) | V08, V04 | `2π`, `π/6`, `5π/6` → `2n`, `п/6`, `5п/6`; `np` → `пp` | `π` becomes `n` (meaning changes). A **Cyrillic `п`** reaches the clipboard. | `Homoglyphs.cyrillic` (`Homoglyphs.swift:7-11`) has no `п`. Map `п` → `π` next to digits/`/` on math lines, and `п` → `n` elsewhere. |
| M6 | **High** (Vision) | V04, V09 | `P(X ≤ 3) ≈ 0.382` → `= 0.382`; `≈ 3.47 h` → `= 3.47 h` | An approximation becomes an equality. Live Text does the same. | Shape check: `≈` has wavy strokes; compare the stroke's vertical spread with `=`'s flat bars (same approach as `isPlusMinus`). |
| M7 | Medium | V03 | `log₃(x + 1)` → `10g3 (x + 1)` | Reads as "10 g 3". | `logLookAlike` (`ScriptRecovery.swift:443-444`) requires a subscript or `(` right after `g`. Here the `3` wasn't subscripted first, so the repair never fires. Allow `[l1I][o0O]g\d+ ?\(`, then subscript the digits. |
| M8 | Medium | V09 | `N(t) = 500e^(0.2t)` → `500e⁰.²ᵗ`; `ln 2` → `In 2`; `t` → `+` | The owner's format needs `^(…)` when a character (`.`) has no superscript glyph; the mixed form is hard to read. `lnLookAlike` (`:440-441`) only fires before a letter or `(`, not before a number. | `script()` (`:1244`): if any character of the run lacks a superscript glyph, emit `^(…)` for the whole run. Extend `lnLookAlike` to `In(?= ?\d)` on lines holding `=`. |
| M9 | Medium | V02 | `d/dx(sin 3x) = 3cos 3x` → `d` ⏎ `dx (sin3x) = 3c0s3x` | The operator fraction isn't rebuilt (the second line's `dy/dx` is); `cos` → `c0s`. | `MathLayout` requires something beside the bar on its line; `d/dx` sits alone. Also `c0s`/`s1n` → `cos`/`sin` on math lines. |
| M10 | Medium (pipeline) | V11 | `F = Gm₁m₂/r²` → `F = G mıᵐZ/r²` | Vision's `m1mz` was wrong too, but the rewrite adds a dotless `ı` and a raised `ᵐ`. | Same guard as P1(c). |

**Why 3:** this is the "3" anchor exactly: common textbook equations (inverse function, vector
magnitude, definite integral, cosine rule, trig solutions) come out meaning-changed — 7 of 11 new
formulas. It is much better than Live Text and than the previous review's held-out math (CER
0.276 → 0.166), but a student still has to retype most formulas.

## Layout & reading order — 7/10

**Works well:**
- V20: a two-column textbook page with a spanning title, figure caption and second-column heading
  comes out in perfect order.
- V21: a sign-in form keeps `Remember me⇥Forgot password?` on one row. Live Text splits it.
- V23: a dark notification keeps `MESSAGES⇥now`. Live Text puts `now` last.
- V22: the nav row is joined with tabs.
- Tuned layout passes 12/13.

**Issues:**

| # | Severity | Case | Problem (expected → actual) | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| Y1 | Medium (pipeline) | V37, V35, V26 | Separate short lines glued: `p. 214, ex. 3–7 (odd)` + `Revise: sine & cosine rules` → one line; footer `…Cookie Settings` + address `Str. Aviatorilor 12…` → one line. Raw Vision and Live Text keep them apart. | Line structure the user can see is lost; they must re-split by hand. | `wrapped()` (`TextReflow.swift:742-761`). (a) The fit test takes the column's right edge from the longest line. In a 3-line block that is only a few characters wider, *any* capitalised next word "wouldn't have fit". (b) When `prev` is the longest line, "no sentence-ending punctuation → joined" treats every label or footer as wrapped. Trust the fit test only when ≥2 lines reach the edge (a real wrap margin); otherwise, an uppercase next line after an unpunctuated line is a new line. |
| Y2 | Low (Vision) | V22 | `Learn more` → `Learn more )` | The pill button's border is read as `)`. | Drop a lone bracket glyph whose height exceeds the line's cap height by >30% (an outline, not text). |

**Why 7:** reading order on real pages, forms and UI is strong and well ahead of Live Text. Y1 is
Medium, not High: nothing is lost, but it recurs (3 new cases).

## Robustness — 5/10

**Works well:** Vision itself read all four new hard images perfectly (raw 4/4):
- Comic Sans on yellow,
- 11 px grey text at 1×,
- white text on a busy concentric-ring background,
- Chalkboard SE on green.

V34 passes end to end. Tuned robustness passes 10/12.

**Issues:**

| # | Severity | Case | Problem | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| R1 | **High** (pipeline) | V36 | `Up to 50% off` → `Up to 50⁰% off` | A number/percentage is corrupted on a sale banner. The earlier re-review's T1 (`%` taken apart) is only half-fixed: the guard stops `⁰/o` but lets an *added* raised `0` through. | `isFaithful` (`ScriptRecovery.swift:1080-1092`) lets up to `chars.count − normal.count` extra script glyphs through. An extra glyph inside the box of a character Vision already read (the `%`'s upper ring) should be rejected, or `%` should be treated as one glyph in `glyphs(_:lineHeight:)` (`:482`). |
| R2 | Medium (pipeline) | V35, V37 | lines glued (Y1) | 2 of the 4 robustness failures are layout, not recognition. | Y1. |

**Why 5:** recognition is robust, because Vision handles these inputs. But the pipeline turned 3 of
the 4 perfect Vision reads into imperfect clipboards, one of them High.

## No-harm — 4/10

What I checked (V38–V44, plain text with traps):
- times, a date and prices: V38 passes;
- `x` as a letter and in `4 x 6`: V40 passes (`4 × 6` is accepted);
- arrows and bullets in prose: V42 passes;
- hyphenated compounds, `a.m.` and a spaced em dash: V43 passes;
- a phone number, an ISBN and an order id: V44 passes;
- plain `1st`/`H2O`/`CO2`: V41. Nothing was subscripted or superscripted; the only errors are
  Vision's `Ist`/`H20`.

Damage also shows up in the other areas' plain-text cases (P1, P2, R1, Y1).

| # | Severity | Case | Problem | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| NH1 | **High** (pipeline) | V39 | `Update to v2.11.0 from ~/Downloads/…dmg, then write to support@example.org if` ⏎ `macOS 14.6.1 still complains.` → `Updateto v2.11.0from~/Downloads/…` and the paragraph not rejoined | A two-line Helvetica paragraph is classified as **code**. `monospaceSpacing` then re-spaces a *proportional* font on a character grid and deletes real spaces. Live Text is perfect. | `isCode` (`TextReflow.swift:561-569`): with 2 lines, `isMonospace` (`:555-559`) compares just two character widths, which match by chance, and one weak signal (`example.org`) makes the pair code. Require ≥3 lines for the monospace test, or measure monospacing from glyph pitch. `ScriptRecovery.monospaceSpacing` should refuse to re-space when the glyph advances aren't uniform. |
| NH2 | High | V13, V14, V36 | see P1, R1 | — | — |
| NH3 | Medium | V16, V26, V35, V37 | see P2, K1, Y1 | — | — |

**Why 4:** the traps built for earlier reviews (ordinals, `%`, JSON, `A0`, old-style figures) are
now mostly safe. But 8 of the 33 new non-math cases still leave with an error our code added, and 4
of those are High. That is an improvement on the re-review's 11/35, but a user still can't trust a
paste of ordinary text without reading it.

## Pipeline code quality — 4/10

**Works well:**
- `swift run --package-path Packages/CaptureKit CaptureKitTests` passes 181/181.
- The OCR pure logic has unit tests (TextReflow ~60 assertions, ScriptRecovery ~36, MathLayout ~26,
  DisplayMath ~15).
- Comments explain *why* each rule exists, with the example that motivated it.
- Vision's own read is kept in `Line.text` and the rebuild goes in `Line.recovered`, which is a good
  separation.
- The `isFaithful` guard is the right idea.

**Issues:**

| # | Severity | Where | Problem | Suggested fix |
|---|---|---|---|---|
| Q1 | High | whole pipeline | **Rules are fitted to seen cases.** Tuned 72% vs new 32% pass. Examples: the prompt regex accepts exactly the prompts in the corpus (`TextReflow.swift:529`); `lnLookAlike`/`logLookAlike` need the exact follower seen before (`ScriptRecovery.swift:440-444`); ∫ works for M08/H04 but not V05. | Keep a rotating held-out set nobody tunes on (e.g. freeze this V set as a regression set and write a fresh one before the next review). Prefer general mechanisms (radical from ink, grid from rules) over per-pattern regexes. |
| Q2 | High | `ScriptRecovery.isFaithful` `:1062-1093` | The no-harm guard only checks *full-size* glyphs. Anything turned into a script (a descender `p`, a `%` ring) or *added* bypasses it. That is the root of P1, R1 and M10. | Script glyphs must match Vision's character case-insensitively when Vision was confident. Added glyphs must lie outside every glyph Vision already read. |
| Q3 | Medium | `ScriptRecovery.swift` (1,258 lines), `DisplayMath.swift` (590) | About 90 bare ratio constants in ScriptRecovery alone (`0.3 *`, `0.45 * cap`, `0.12 * refHeight`…), each tuned to a font seen in the corpus. The interactions are hard to reason about (V13/V14: two thresholds combine into a false subscript). | Name the thresholds, group them per concept (x-height, descender depth, script offset), and test each against several fonts' real metrics (Georgia, Avenir, Optima, Hoefler, Times). |
| Q4 | Medium | `TextReflow.isMonospace` `:555-559`, `wrapped` `:742-761` | Decisions made from 2 samples (two character widths; a column edge set by one line). | Minimum-evidence rules (≥3 lines, ≥2 lines at the edge) before trusting a statistic. |
| Q5 | Medium | `TextRecognizer.recognize` `:28-74` | Every line goes through `lineGlyphs`/Otsu/blob analysis and possibly several extra Vision re-reads (`readLine`), plus a second full Vision pass when code is suspected. Debug-build latency: median 374 ms, p90 0.9 s, 2.2 s on a 7×4 table. | Skip `ScriptRecovery` on lines with no raised/lowered ink cheaply (first pass on the line's ink profile), and cache `InkMap` per image instead of per line. |
| Q6 | Low | `Homoglyphs.swift:7-11` | The Cyrillic map lacks `п`, `г`, `л`, `и` look-alikes that Vision does emit (V04, V08). | Extend the table; add a test with `п`. |

**Why 4:** clean, commented Swift with real unit tests. But the architecture accumulates
case-specific rules faster than it generalizes, and its safety guard has the gap that causes most of
the silent corruption. "Good code with noticeable issues", at the low end.

## Cross-cutting issues

1. **Overfitting.** Every earlier held-out case was tuned against after the re-review (H: 2/35 →
   19/35), while cases written today pass 14/44. Pass rates on H/N now overstate quality as much as
   the original corpus did. Only V (this set) is unseen.
2. **Script recovery can still rewrite ordinary text** through the two holes in `isFaithful`
   (scripts and additions): P1, R1, M10.
3. **Minimum-evidence heuristics:** the code-vs-prose and wrap-vs-new-line decisions trust one or
   two measurements (NH1, Y1, K1). All three failure modes turn a perfect Vision read into a worse
   clipboard.
4. **Glyph-level misreads Live Text shares** (`≈`→`=`, `±`→`=`, `π`→`n`, `Ș`→`Ş`, em dash → hyphen,
   backtick → quote). None are our bugs, but in math and tables they change meaning, and several can
   be fixed by the shape checks the pipeline already uses for `±` and `θ`.

## Top fixes (ranked by impact ÷ effort)

1. **Close the `isFaithful` holes and stop descender subscripts** (`ScriptRecovery.swift:590-596`,
   `:1062-1093`). Script glyphs keep Vision's letter when Vision was confident; no added glyph
   inside an already-read glyph; a glyph whose top sits at x-height is a descender, not a subscript;
   never subscript a word's first glyph. *Fixes V13, V14, V36, V11; small change, High impact.*
2. **Require minimum evidence in `isCode` / `monospaceSpacing` / `wrapped`** (`TextReflow.swift:555-569`,
   `:742-761`; `ScriptRecovery.monospaceSpacing` `:362`). Monospace needs ≥3 lines or uniform glyph
   pitch; trust the fit test only with ≥2 lines at the edge; widen the prompt pattern to zsh/bash
   defaults. *Fixes V39, V35, V37, V26.*
3. **Tables: use gridlines and ignore spanning cells when building column bands** (`TextReflow.swift:429`,
   `:856`). *Fixes V29, V30: the wrong-column Highs.*
4. **Radical and ∫ from ink, not from Vision's character** (`ScriptRecovery.swift:463-466`,
   `DisplayMath.swift:202-217, 407`), plus re-reading a lost numerator above a fraction bar.
   *Fixes V01, V05, V07, V10 and earlier H06 — the math Highs.*
5. **Cheap symbol maps:** `п` → `π`/`n` (`Homoglyphs.swift`); `Ş/Ţ` → `Ș/Ț` when Romanian is on;
   `≈` and `±` shape checks; `log`/`ln` look-alikes before digits (`ScriptRecovery.swift:440-444`);
   `^(…)` for runs with an unscriptable character (`:1244`). *Fixes V03, V04, V08, V09, V14, V31
   partly.*
6. **Process:** keep `ThirdReviewCases.swift` as a frozen regression set, and write the next held-out
   set before tuning, not after.

## Method & limits

- **Cases:** 44 new cases in `tools/ocr-bench/Sources/ocr-bench/ThirdReviewCases.swift` (V01–V44),
  added to `cases` in `Cases.swift` line 6 (the only harness change). The mix:
  - 11 math (IB: inverse functions, derivatives, log equations, binomial, a definite integral, a
    sum, vectors, trig at 1×, an exponential slide, the cosine rule, gravitation);
  - 6 prose;
  - 2 lists + 1 list-like robustness case;
  - 5 code (JS, C, zsh, JSON, Python at 1×);
  - 5 tables (Sheets at 1×, a timetable with a merged row, a borderless lab table, a dark GitHub
    table at 1×, a Wikipedia table);
  - 4 layout/UI;
  - 4 robustness;
  - 7 no-harm.

  Fonts deliberately not in the tuned sets: Avenir, Avenir Next, Optima, Charter, Iowan Old Style,
  Hoefler Text, Gill Sans, Futura, Trebuchet, Tahoma, Seravek, PT Serif/Sans/Mono, Andale Mono,
  SF Mono, Comic Sans, Chalkboard SE. Six cases are at 1×; four have dark or coloured backgrounds.
- **Ground truth** was written before any output was seen. I looked at every rendered image before
  running recognition. The one change after writing: I added an accepted variant to V22 (logo on its
  own line above the nav). That was done after viewing the render and *before* seeing any output. No
  ground truth was changed to match an output.
- **Runs:** `ocr-bench run --livetext --rawvision` over all 152 cases, debug build, on the owner's
  Mac (macOS 26 / Darwin 25.6). The Vision languages were `en-US` + `ro-RO`.
  - Rendering was offscreen (WKWebView in a never-shown window); no window was shown or activated.
  - `dump V16 V26` was used for Vision's candidates.
  - Evidence panels in `docs/reviews/2026-09-29-ocr/` were composed with `tools/ocr-bench/tools/evidence.swift`:
    - `01-math-new.jpg` (V01 V05 V07 V10),
    - `02-math-inline.jpg` (V04 V08 V09 V11),
    - `03-noharm-damage.jpg` (V13 V14 V36 V39),
    - `04-merged-lines.jpg` (V26 V35 V37),
    - `05-tables.jpg` (V29 V30 V31),
    - `06-good.jpg` (V20 V25 V32 V06).
- **Pipeline-introduced** errors were judged case by case against the raw-Vision column. A CER
  comparison alone misses them, because raw Vision's layout is usually worse.
- **Not checked:**
  - release-build latency (no release rebuild, to keep the load light);
  - the real app's hotkey → clipboard path (the harness calls the same `recognize` entry point);
  - CleanShot X itself (not installed);
  - real screenshots of real apps: all cases are HTML renders, which are cleaner than, e.g., a
    compressed video frame or a photographed worksheet;
  - checklists (L05-type) were not re-tested.
- **Hardest / arguably unfair cases:**
  - V08: 14 px Trebuchet at 1× with `π`, near the limit of what Vision can read.
  - V11: subscripts inside a fraction's numerator.
  - V09: the owner's `^(0.2t)` rule for a decimal exponent is strict; `e⁰.²ᵗ` is readable if
    ugly.
  - V12 and V19: fail only on glyph-level dashes, which Live Text also misses.

  Even with all five counted as passes, the new-set pass rate would be 19/44 and the scores above
  would not change.
- **Trend:** 2026-09-28 review 3/10 → re-review 4/10 → this review 4/10. On cases unseen at review
  time, CER went 0.177 → 0.050 and pass rate 2/35 → 14/44. That is real progress, but it isn't yet
  enough to cross into 5–6 while math changes meaning and plain text is still silently damaged.
