# Capture Text (OCR) — speed + accuracy review, 2026-09-29

Independent review of BetterScreenshot's **Capture Text** feature (⌘⇧7: drag a region and its text goes on
the clipboard), on branch `ocr-structure-math` at commit `ee02d3f`. The main focus is **speed** with math on
and off, in debug and release builds: where the time goes, and a ranked list of changes. The review also
measures accuracy on 30 new held-out cases (`W01`–`W30`). No product code was changed. All numbers come
from temporary instrumentation in a review worktree (see *Method & limits*).

**Terms used in this report**
- **Vision**: Apple's on-device OCR (`VNRecognizeTextRequest`, "accurate" level).
- **Main pass**: the one Vision call on the whole capture.
- **Re-read**: the pipeline paints a small synthetic image (for example a straightened line, or a glyph
  behind an `a = ` prefix) and calls Vision on it again (`TextRecognizer.readLine`).
- **Code pass**: a second full Vision call with language correction off. It runs only when the capture
  looks like code.
- **InkMap**: an Otsu-binarised crop plus its 8-connected blobs (`InkMap.swift`).
- **CER**: character error rate, the edit distance divided by the expected length.
- **Math on/off**: the setting Settings → Capture → Recognize math (`CaptureSettings.captureTextMath`,
  passed as `TextRecognizer.recognize(…, math:)`).
- **p90**: the 90th percentile.
- **Cold**: Vision's text model isn't loaded in the process. This happens on the first capture after
  launch, and again after about 20 s idle.
- **Dry-run gate**: recommendation #1 (see below).
- **Live Text**: macOS's own copy-text-from-image feature, used as a reference.
- **IB**: International Baccalaureate, the owner's school programme; the W cases imitate its material.
- **IoU**: intersection over union of two boxes.

Relative paths such as `runs/…` and `runs-prev/…` point to measurement files under
`tools/ocr-bench/` **in the review worktree**
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot/.claude/worktrees/agent-a8fe3ee01f174dc6d/`.
They are not committed and disappear if that worktree is removed. Source paths
(`DisplayMath.swift:146` etc.) are under `Packages/CaptureKit/Sources/CaptureKit/`, with line numbers
at commit `ee02d3f`.

## Scoreboard

Scale: **8–10** basically perfect · **4–7** good, with noticeable issues · **1–3** not to our standard.

Speed calibration: **9** means a typical paragraph takes ≤ 150 ms in a release build and a dense
table or equation page takes ≤ 400 ms. **6** means 0.5–1 s pauses on dense captures. **3** means common
captures take more than 1.5 s.

Accuracy anchors: **3** means common inputs come out scrambled or with changed meaning. **6** means
prose, lists and code are right, and math and tables need under a minute of cleanup. **9** means right
first time, apart from rare glyph misreads that Live Text also makes.

| Dimension | Evidence (release build, warm unless noted) | Score |
|---|---|---|
| **Speed, math on (as shipped)** | Paragraphs: median 80 ms, p90 143 ms. After 20+ s idle, add +60 ms (P02 140 → 199 ms). **Tables: median 308 ms, p90 459 ms, max 571 ms** (and +100 ms after idle). Math p90 274 ms. About a third of all math-on time goes to DisplayMath re-reads for rows that are then thrown away | **7/10** |
| Speed, math on, **after recs #1 + #2** | Tables median 84 ms, p90 116 ms. Math median 86 ms, p90 167 ms, max 227 ms. All captures p90 165 ms. Same output on all 188 cases | (would be 9/10) |
| **Speed, math off** | Median 70 ms, p90 140 ms, max 235 ms. Paragraphs: median 78 ms. What's left is almost all the main Vision pass (the floor) | **9/10** |
| **Accuracy, math on (W cases)** | 14/30 pass, mean CER 0.080 (raw Vision: 3/30, 0.185). Tables 3/3 and code 2/3 are right. Prose 7/10 and lists 1/2, but **the math layer corrupts plain prose**: `attachθd thθ … lθt` (W13) and `Δdd` (W16). Math 0/10 exact. 3 formulas change meaning (W01 loses the `=`, W08 loses `n/2`, W09 gets a garbage `²ᵃ` and drops an `s`) | **5/10** |
| **Accuracy, math off (W cases)** | 14/30 pass, mean CER 0.127. Prose and lists are clean: the only errors are Vision's own `l`/`I` confusion and one paragraph split. Tables 3/3 and code 2/3 are right. Math comes out at raw-Vision quality (W04 `dy/dx = …` becomes tab soup, `∫₀^π` loses its sign) | **5/10** |
| **Overall** | Fast enough already, and ~1 day of safe work makes it fast everywhere. Accuracy is the limit: math-on beats raw Vision by a wide margin on math, but it silently damages ordinary words | **5/10** |

Is the on/off difference big enough? **As shipped, yes:** median 1.38×, tables 3.9×, math 2.8×. But
most of that gap is waste (rec #1). After recs #1 and #2, math-on costs **≤ 15 ms more than off on
prose, lists, code, tables and layout**. On math captures it still costs **~45 ms more (≈ 2×)**, at a
median of 86 vs 42 ms. So once fixed, the setting **trades accuracy on formulas, not speed**: math-on
passes 129/188 cases vs 95/188 off. Math-on then no longer needs to be avoided for speed. Only the "off
= ≈3× faster" wording in the settings help (and in `CLAUDE.md`) would need updating to say "slightly
faster on formula-heavy captures".

## Speed

All times are wall-clock for `TextRecognizer.recognize` alone (no screen grab, no clipboard write). Each
case runs once, on the owner's M3 MacBook, over the `tools/ocr-bench` corpus of 188 cases (158 existing
plus the 30 new `W*`). The shipped app is a **release** build: `scripts/package-release.sh` runs
`build-app.sh release universal`, and `/Applications/BetterScreenshot.app` came from that. So the release
tables are what users feel. The first case of each run is cold; the rest are warm.

### Release, as shipped (188 cases)
| Area | n | on median | on p90 | on max | off median | off p90 | off max | on/off (median of per-case ratios) |
|---|---|---|---|---|---|---|---|---|
| prose | 39 | 80 | 143 | 283 | 78 | 126 | 233 | 1.03× |
| lists | 11 | 137 | 202 | 261 | 88 | 131 | 131 | 1.20× |
| code | 21 | 198 | 313 | 487 | 151 | 181 | 235 | 1.30× |
| tables | 25 | 308 | 459 | 571 | 70 | 92 | 147 | 3.92× |
| math | 56 | 126 | 274 | 422 | 42 | 70 | 139 | 2.76× |
| layout | 20 | 114 | 201 | 258 | 88 | 151 | 201 | 1.13× |
| robustness | 16 | 68 | 108 | 154 | 55 | 79 | 85 | 1.10× |
| **all** | 188 | **126** | **307** | 571 | **70** | **140** | 235 | 1.38× |

The whole corpus takes 29.8 s with math on and 14.9 s with it off (2.0×). Passes: 129/188 on vs 95/188 off.

### Release, math on with rec #1 (dry-run gate) and rec #2 (re-read memo)
| Area | n | on median | on p90 | on max | off median | off p90 | off max | on/off |
|---|---|---|---|---|---|---|---|---|
| prose | 39 | 80 | 133 | 265 | 78 | 126 | 233 | 1.04× |
| lists | 11 | 98 | 140 | 142 | 88 | 131 | 131 | 1.08× |
| code | 21 | 164 | 238 | 261 | 151 | 181 | 235 | 1.06× |
| tables | 25 | 84 | 116 | 161 | 70 | 92 | 147 | 1.18× |
| math | 56 | 86 | 167 | 227 | 42 | 70 | 139 | 1.80× |
| layout | 20 | 95 | 161 | 200 | 88 | 151 | 201 | 1.07× |
| robustness | 16 | 59 | 82 | 91 | 55 | 79 | 85 | 1.04× |
| **all** | 188 | **86** | **165** | 265 | 70 | 140 | 235 | 1.11× |

The corpus takes 18.8 s (−37 %), still 129/188 passes, and **all 188 outputs are byte-identical** to the
shipped pipeline. With the gate alone, the corpus takes 19.8–20.0 s, math p90 is 194 ms and max 360 ms.
The memo brings math p90 down to 167 ms and max to 227 ms.

### Debug, as shipped (158 existing cases; the W cases were added after this run)
| Area | n | on median | on p90 | on max | off median | off p90 | off max | on/off |
|---|---|---|---|---|---|---|---|---|
| prose | 29 | 225 | 432 | 835 | 112 | 206 | 340 | 2.19× |
| lists | 9 | 576 | 812 | 965 | 145 | 360 | 470 | 2.53× |
| code | 18 | 624 | 892 | 959 | 379 | 495 | 611 | 1.52× |
| tables | 22 | 1140 | 1736 | 2229 | 226 | 279 | 309 | 5.28× |
| math | 46 | 394 | 672 | 932 | 70 | 164 | 211 | 4.70× |
| layout | 18 | 683 | 1052 | 1219 | 323 | 583 | 716 | 1.66× |
| robustness | 16 | 184 | 409 | 566 | 83 | 102 | 229 | 1.88× |
| **all** | 158 | 410 | 1006 | 2229 | 131 | 383 | 716 | 2.42× |

Debug is about 3× slower than release on the math-on path, because the pixel passes are unoptimised
Swift loops. This only matters for local testing. But `scripts/build-app.sh` **defaults to debug**, so a
locally built `dist/BetterScreenshot.app` makes Capture Text feel ~3× slower than the release users get.
Judge speed only on a release build (`scripts/build-app.sh release`).

### Cold vs warm (release)

These are single runs of paragraph P01/P02 and table T01, math on, with ±10 % noise.

| Situation | P01 paragraph | P02 paragraph | T01 table |
|---|---|---|---|
| Warm, steady state (fastest of 3) | 123 | 140 | 299 |
| Fresh process, no warm-up (3 runs) | 244–318 | — | 359–366 |
| Fresh process, the app's `warmUp()` first (blank 32×32 image; takes ~82 ms) | 180–198 | — | 347–369 |
| Fresh process, a warm-up on a small **text** image first (takes ~142 ms) | 127–136 | — | 351–369 |
| Same process, **25 s idle**, no warm-up | — | 199 | 416 |
| 25 s idle, then `warmUp()` (blank; takes only 23 ms, so it barely touches the model) | — | 181 | 399 |
| 25 s idle, then a text-image warm-up (takes ~75 ms) | — | **142** | 440 |

Going cold costs a paragraph **+60 ms** after idle and **+120–190 ms** in a fresh process. The app
already calls `TextRecognizer.warmUp()` when the selection overlay appears
(`App/Capture/CaptureCoordinator.swift:100`). But warming up on a blank image gets back only about
a third of that cost after idle, because Vision finds no text and skips the recognizer. **A warm-up on a
tiny image with real text gets all of it back** for the main pass (rec #3). The table's extra +100 ms
after idle did *not* go away with either warm-up. It probably comes from the per-line work: CPU clocks
ramping back up, and/or the language-correction-off re-read setup, which the warm-up doesn't exercise.
It is a minor effect once rec #1 removes most of the table's re-reads.

## Where the time goes (math on)

### Whole corpus, release, as shipped (profiled run, 188 cases, 30.4 s)

| Stage (`TextRecognizer.recognize`) | Calls | ms | Share |
|---|---|---|---|
| Main Vision pass (`perform([textRequest, qrRequest])`, line 22) | 188 | 12,716 | 41.8 % |
| **DisplayMath** (`DisplayMath.rebuilding`, line 94) | 188 | 12,119 | **39.8 %** |
|   … of which Vision re-reads | 622 | 11,449 | 37.6 % |
| Per-line `ScriptRecovery.recover` (confident) | 1,093 lines | 1,884 | 6.2 % |
|   … of which Vision re-reads | 84 | 1,179 | 3.9 % |
| Per-line shaky-line recover (confidence < 0.9) | 83 lines | 1,182 | 3.9 % |
|   … of which Vision re-reads | 67 | 1,127 | 3.7 % |
| Code pass (second full Vision call, language correction off) | 21 | 978 | 3.2 % |
| All InkMap builds (Otsu + blobs) | 3,071 | 944 + 288 | 4.0 % |
| `dashesAndDots` + `relationSymbols` + `missingFullStop` | 3 × 1,119 | 660 | 2.2 % |
| `cellLines`, `bracketLines`, `monospaceSpacing` (incl. their 21 re-reads) | — | 642 | 2.1 % |
| `TextReflow.paragraphs` (incl. `GridLines` 63 ms, bar measuring 73 ms) | 188 | 167 | 0.6 % |
| Upscale 1× → 2× | 188 | 35 | 0.1 % |

A re-read costs **~18 ms** on average, about a quarter of a main pass (~68 ms). What makes math-on slow
isn't pixel work. It is the **number of Vision calls**.

### Representative cases (release, ms per stage; "Vision calls" = main + code + re-reads)

As shipped:

| Case | What | Total | Main | Shaky recover | Recover | DisplayMath | Code pass | Other | Vision calls | Lines |
|---|---|---|---|---|---|---|---|---|---|---|
| P01 | slide paragraph (cold, first case of the run) | 256 | 236 | · | 9 | · | · | 11 | 1+0+0 | 6 |
| W10 | notes: heading + 2 paragraphs | 157 | 123 | · | 20 | · | · | 14 | 1+0+0 | 6 |
| V20 | two-column textbook page | 218 | 184 | · | 13 | · | · | 21 | 1+0+0 | 16 |
| T03 | spreadsheet, 25 lines | 469 | 141 | · | 8 | **315** | · | 5 | 1+0+22 | 25 |
| V33 | Wikipedia table, 25 lines | 578 | 82 | · | 7 | **481** | · | 8 | 1+0+24 | 25 |
| W20 | bordered chemistry table | 328 | 60 | · | 6 | **258** | · | 4 | 1+0+15 | 15 |
| W17 | Python in an editor | 451 | 101 | · | 5 | **261** | 64 | 20 | 1+1+9 | 11 |
| C05 | code with line-number gutter | 303 | 68 | 1 | 3 | **177** | 35 | 19 | 1+1+11 | 10 |
| M04 | quadratic formula | 209 | 31 | 47 | · | 129 | · | 2 | 1+0+8 | 3 |
| V06 | ∑ with limits | 157 | 46 | 2 | 1 | 105 | · | 3 | 1+0+6 | 5 |
| H01 | geometric series, 3 lines | 578 | 42 | 94 | 16 | 424 | · | 2 | 1+0+21 | 3 |
| W08 | arithmetic sequence | 320 | 37 | 122 | · | 157 | · | 4 | 1+0+14 | 2 |
| W23 | slide with inline formulas | 201 | 70 | · | 3 | 124 | · | 4 | 1+0+4 | 4 |

With the dry-run gate (rec #1). The outputs are identical:

| Case | Total | Main | Shaky recover | DisplayMath | Code pass | Vision calls |
|---|---|---|---|---|---|---|
| T03 | 469 → **162** | 146 | · | 315 → 4 | · | 1+0+**0** |
| V33 | 578 → **104** | 78 | · | 481 → 11 | · | 1+0+**0** |
| W20 | 328 → **79** | 59 | · | 258 → 9 | · | 1+0+0 |
| W17 | 451 → **194** | 100 | · | 261 → 5 | 65 | 1+1+0 |
| C05 | 303 → **132** | 68 | 1 | 177 → 2 | 38 | 1+1+1 |
| M04 | 209 → **83** | 31 | 49 | 129 → 2 | · | 1+0+2 |
| V06 | 157 → 128 | 41 | 2 | 105 → 82 | · | 1+0+6 |
| H01 | 578 → 347 (→ **215** with the memo) | 38 | 80 | 424 → 211 | · | 1+0+17 |
| W08 | 320 → 262 (→ **202** with the memo) | 37 | 119 | 157 → 103 | · | 1+0+12 |
| W23 | 201 → **82** | 69 | · | 124 → 5 | · | 1+0+0 |

**Why tables and code were slow.** `DisplayMath.rebuilding` gathers "mathy" lines into clusters.
`isMathy` (`DisplayMath.swift:98`) allows at most one ordinary word of 4+ letters, so short cells like
`19.0`, `Sofia` and `mid = (lo + hi) // 2` all count. Every table and most code blocks therefore become
one big cluster. `rebuild` then **parses every row, and in doing so re-reads every glyph run with
Vision**. The check that the row has any structure (`node.hasStructure && layout.needed`,
`DisplayMath.swift:149`) comes *after* those re-reads, and for a table it fails every time. Of 622
DisplayMath re-reads, at least 534 (86 %) fed rows that were then thrown away.

**After recs #1 and #2, the remaining math-on cost** over the corpus (18.8 s total) splits up like this:

| Part | Share |
|---|---|
| Main Vision pass (the floor; math off is essentially just this) | 66 % |
| Re-reads for real math (DisplayMath 82, recover 76, shaky recover 37, cells/brackets 20) | 16 % |
| Code pass | 5.5 % |
| InkMaps | 4.7 % |
| Everything else | ~8 % |

On math captures, re-reads are still about half the time (for example H01: 17 re-reads ≈ 300 ms before
the memo).

## Accuracy on the new W cases

30 cases written **before any output was seen**: 9 math, 10 prose (5 of them "no-harm" probes), 2 lists,
3 code, 3 tables, 1 slide, 2 layout. The mix is realistic IB-student material (physics data booklet,
chemistry, maths, TOK notes, Python/Java, timetables, chat and dialogs). The file is
`tools/ocr-bench/Sources/ocr-bench/FourthReviewCases.swift`. On review, all ground truths match their
HTML, so none were changed. "Raw" means Vision's own lines, in order, with no pipeline.

| | Pass | Mean CER |
|---|---|---|
| Math on | **14/30** | 0.080 |
| Math off | **14/30** | 0.127 |
| Raw Vision | 3/30 | 0.185 |

By area (on / off / raw):

| Area | Math on | Math off | Raw | Notes |
|---|---|---|---|---|
| Tables (W20–22) | 3/3 | 3/3 | 0/3 | Rows, tabs and empty cells all right, even with math off |
| Code (W17–19) | 2/3 | 2/3 | 0/3 | W18 drops the final lone `}` |
| Prose (W10–14, W26–30) | 7/10 | 7/10 | 2/10 | On-only damage in W13. W14: a wrapped paragraph is split after `used up.`. W30: `CtrI` (Vision) |
| Lists (W15–16) | 1/2 | 1/2 | 0/2 | W16 on: **`Δdd`** for "Add" |
| Layout (W24–25) | 1/2 | 1/2 | 1/2 | W25: the time stamp goes to the end instead of the sender's row |
| Math (W01–09, W23) | 0/10 | 0/10 | 0/10 | On: CER mostly lower. See below |

**Errors the pipeline adds (math on; neither math-off nor raw Vision has them):**
1. **W13, 1× email: `I have attachθd thθ second draft … Could you lθt me know`.** The cause is
   `ScriptRecovery.swift:67`. The trig flag is set by `(?<![A-Za-z])(?:sin|cos|tan|sec|csc|cot)`, which
   also matches inside ordinary words: **"second"**, "since", "single", "cost", "tank", "secure". With
   the flag on, any glyph `isTheta` accepts becomes `θ` (`:903`), and at 1× density that includes `e`.
   The evidence: the only W13 line that was damaged is the one containing "second". The next line,
   with just as many `e`s, came through clean. Prose containing "since" or "second" is very common.
   This is the most damaging finding, because it corrupts non-math text silently.
2. **W16, Cochin list: `Δdd 2 g of calcium carbonate`.** `isDelta` (`:136`, applied at `:889`) accepts
   a serif `A` whose feet nearly close. No word-level check is made.
3. **W01: `v² = u² + 2as` → `v²u2² + 2as`.** The `=` is lost and `u` is duplicated, which changes the
   meaning. Raw Vision had `V=u2+2as`, so the rebuild made it worse. Also `½at2` isn't fixed to `½at²`.
4. **W08: `Sₙ = n/2(2u₁ + …)` → `Sₙ = -(2u₁ + …)`.** The inline stacked `n/2` becomes a minus sign,
   which changes the meaning. Also `uₙ` → `Unₙ` (duplicated n).
5. **W09, 1×: `9.81 m s⁻² … 10⁸ m s⁻¹` → `9.81 ms 2²ᵃ … 108 m⁻¹`.** A garbage `²ᵃ` is added and the `s`
   is dropped. The `10⁸` exponent is still missed.
6. **W03 / W07: `ⁿ` → `^П`, `π` → `^П`.** This is a **Cyrillic** Pe. `Homoglyphs` should map it to `n`
   (or to `π` in a math context).

**Wins over raw Vision (math on):** W04 `dy/dx = dy/du X du/dx` is nearly exact (raw was 8 separate
lines, and math-off produced tab soup; only `X` → `×` is missing). W07 is `∫₀^П sin x dx = 2` (raw:
`П` on its own line). The W08 subscripts are right. W20–22 tables are perfect (raw CER 0.33–0.78).

**Still wrong in both modes:** W02 `K_c = [NH₃]²/([N₂][H₂]³)` comes out as garbage. W05
`Z = (X − μ)/σ` comes out as `X-u\nZ = -`. W06 `2x²` loses its square, and Vision drops the spaces in
`are x = 1 and x`. W23 `π` → `n`, `θ` → `e`, and `A = πr²` loses its `²`.

## Recommendations (ranked)

Ranking = (speed gain × safety) ÷ effort. "Measured" means an experiment ran in the review worktree
over all 188 cases with the outputs compared case by case. Line numbers are at `ee02d3f`.

### Speed

**1. DisplayMath dry-run gate. Parse each row once with Vision stubbed out, and re-read only rows that
can have structure.**
- **Where:** `DisplayMath.swift:146–153` (`rebuild`, the `rows().compactMap` loop), plus the private
  `read` at `:532`.
- **What:** Add a `dry` flag to `Layout`. When it is set, `read` returns a fixed placeholder (`"lim"`)
  instead of painting and re-reading. Run `parse(row)` dry first, and skip the row unless
  `hasStructure && needed`. Then run the real parse.
- **Measured:** DisplayMath 12.1 s → 1.7 s. Re-reads 622 → 88. Corpus 30.4 → 19.8 s (−35 %). Tables
  median 308 → 84 ms, p90 459 → 117 ms. Code median 198 → 165 ms. **0/188 outputs changed**
  (`runs/exp-dryrun.json` vs `runs/rel-on-prof.json`, reproduced in `runs/gate-prof.json`).
- **Why it's safe by construction:** Every structure decision in `parse` (fraction, big operator,
  bracket, matrix, `=`) is geometric (`isBar`, `operatorSymbol`, `bracket`, `equalsAxes`). The one
  decision that reads text, `lim` detection (`:502`), sees `"lim"` in the dry run, so it can only
  accept *more* rows. The stub never returns nil, while real reads can fail, which again only makes the
  dry run accept more. So every row the real parse keeps also passes the dry run.
- **Accuracy risk:** none. **Effort:** ~15 lines.

**2. Remember re-reads per capture: identical synthetic image, same answer.**
- **Where:** `TextRecognizer.readLine` (`TextRecognizer.swift:270`).
- **What:** A dictionary keyed by a hash of (width, height, pixel bytes), created in `recognize` and
  passed down (or held in a task-local). The same images come up repeatedly: the shaky pass and the
  following confident pass paint the same word images, and DisplayMath's prefixed/unprefixed reads
  repeat too.
- **Measured on top of #1:** 45 of 260 re-reads (17 %) were duplicates. Corpus 20.0 → 18.8 s. Math
  p90 194 → 167 ms, max 360 → 227 ms. H01 360 → 215 ms, V10 210 → 149 ms. **0/188 outputs changed.**
  Vision gives the same answer for the same image: 124/124 identical in the previous reviewer's
  micro-benchmark.
- **Accuracy risk:** none. **Effort:** ~15 lines.

**3. Warm up Vision on real text, not on a blank image.**
- **Where:** `TextRecognizer.warmUp()` (`TextRecognizer.swift:328`), called from
  `CaptureCoordinator.swift:100` while the user drags.
- **What:** Draw 1–2 words with CoreText into a ~200×40 image and run the language-correction-on
  request on it. Optionally also run a language-correction-off `readLine` on it, for the math path.
- **Measured:** first capture after 25 s idle: P02 199 ms (no warm-up) / 181 (blank warm-up) /
  **142** (text warm-up). Fresh process: 244–318 / 180–198 / **127–136**. It costs ~75–140 ms, but in
  the background, hidden behind the drag.
- **Accuracy risk:** none. **Effort:** ~10 lines.

**4. Overlap or shrink the code pass.**
- **Where:** `TextRecognizer.swift:98–103`.
- **What:** It costs 49 ms per code capture (21 cases, 1.03 s): 25–35 % of a code capture after #1.
  Two options:
  - (a) Set `rawRequest.regionOfInterest` to the union of the code-like lines. This helps when code is
    part of a larger capture, and not at all for pure code.
  - (b) Decide `containsCode` from the main-pass lines right after the main pass, start the raw pass on
    a background queue, and join before use. The overlap is limited by the line loop's CPU time
    (~20–40 ms on code), because Vision calls don't overlap one another (see #9).
- **Expected gain:** ~20–40 ms on code captures.
- **Accuracy risk:** low for (a) (IoU matching stays the same), low for (b) (the decision has to use
  the same lines).
- **Effort:** medium. Do it only after #1–#3.

**5. Compute `lineGlyphs` once per line.**
- **Where:** `ScriptRecovery.swift:171`. Callers: `missingFullStop :256`, `relationSymbols :271`,
  `dashesAndDots :301`, `recover :65`, `monospaceSpacing :394`, each with the same `rect` and `others`.
- **What:** Memoise per (rect, others) within a capture.
- **Measured cost it would remove:** ≈ 275 ms over 188 cases (~1.5 ms per capture, up to ~10 ms on
  25-line tables).
- **Accuracy risk:** none. **Effort:** small. Worth doing, but only as tidying.

**Evaluated and not recommended.** Each was measured, or rejected on the numbers:

6. **One InkMap for the whole image.** All InkMap work is 4.7 % of time, ~6 ms per capture. A single
   global Otsu threshold would not match the per-line crops wherever the background changes within a
   capture: dark-mode panels, zebra rows, coloured slide bands (cases like W14, V32 and W23). Every
   glyph threshold in `ScriptRecovery` was tuned on per-line maps. It saves little and risks a lot.
7. **Skip `ScriptRecovery.recover` on lines with no raised or lowered ink.** Already done:
   `recover` returns at `ScriptRecovery.swift:74` unless it finds scripts or symbols. On those lines
   only `lineGlyphs` runs, which #5 covers.
8. **Batch re-reads into one Vision call** (stacking 2, 4 or 8 synthetic images per image). Faster per
   read (17.6 → 12.6 / 10.6 / 7.9 ms), but **22–28 % of reads came back different** even ignoring
   spaces (97/124, 94/124 and 89/124 identical; `runs/batchbench*.log`). Vision's line grouping and
   case/size judgement depend on the neighbouring images.
9. **Run re-reads in parallel** (`DispatchQueue.concurrentPerform`). 2,005–2,849 ms vs 2,177–2,670 ms
   sequential: **no gain**, because Vision serialises internally. The CPU-only per-line work that could
   run in parallel is ~7 ms per capture in total.
10. **Lighter Vision settings.**
    - `.fast` for re-reads: −2.6 s over the corpus, but **17 passes are lost** (M04, M08, M09, M12,
      V07, V10, H04…) against 1 gained, and CER is higher on 30 cases.
    - Dropping the QR request: no measurable gain (main pass 12.6 vs 13.0 s), and **R07 breaks**.
    - The main pass must stay `.accurate` with language correction on.
11. **Cap re-reads on shaky lines** (skip the shaky pass, or stop re-reading after the first unsure
    read, since the result is thrown away when `sure == false`).
    - Skipping the shaky pass saves ~0 s (the confident pass then does the work), **loses 4 passes**
      (M13, M21, V07, V10) and gains 1 (H03).
    - Stopping early skipped **1 read** in the whole corpus: no gain.
12. **Cache `GridLines`.** Already built lazily once per capture (`TextRecognizer.swift:128`). It
    costs 63 ms over the whole corpus.
13. **Avoid the second code pass entirely.** Language correction on would cut `items.reduce(` apart,
    and a first pass with it off would damage prose. Keep the pass, and see #4.

After #1–#3, the **main Vision pass is two-thirds of the time**, and no safe way was found to make it
cheaper. It is also what math-off costs. Math-on speed is then **8–9/10** by the calibration above.

### Accuracy (ranked by damage ÷ effort)

**A. Fix the trig flag** (`ScriptRecovery.swift:67`).
- Require the function name to be followed by a non-letter or an argument: for example
  `(?<![A-Za-z])(?:sin|cos|tan|sec|csc|cot)(?![a-z]{2})` plus the existing `sinx` handling. Or check
  the word against `WordList` first.
- This stops `θ` being injected into prose containing "second" or "since" (W13).
- Add W13-style no-harm cases at 1×: "since", "second", "cost", "tank".

**B. Word-level guard for `Δ`, `π`, `θ` and `∫` repairs** (`ScriptRecovery.swift:885–906`).
- Don't replace a letter inside a token that is an ordinary dictionary word (`WordList`), or that is
  followed by 2+ lowercase letters. This fixes `Δdd` (W16) and protects "Tank", "Tell", "Add" and
  "Assume".

**C. Map Cyrillic `П` inside math output** (`Homoglyphs` pass on `recovered`). Use `n` as a
superscript, or `π` when it sits full-size between math tokens. Fixes W03 `^П` and W07 `∫₀^П`.

**D. Look into the W01, W08 and W09 rewrites that change meaning.**
- W01 loses the `=`.
- W08: an inline stacked fraction becomes `-`.
- W09: `²ᵃ` is added and an `s` is dropped.

All three pass the no-harm guard (`isFaithful`), so check that the guard rejects **dropped** full-size
glyphs (`=`, `s`) as strictly as changed ones.

**E. Smaller items.**
- `×` for `X` between two fractions (W04).
- Keep a lone final `}` (W18).
- Join a paragraph whose line ends with `.` when the next line continues at the same indent and pitch
  (W14).

## Method & limits

- **Code under test:** `ocr-structure-math` at `ee02d3f`, with profiling added in the review worktree
  (`agent-a8fe3ee01f174dc6d`):
  - `Packages/CaptureKit/Sources/CaptureKit/OCRProfile.swift`, plus `inStage`/`time` wrappers in
    `TextRecognizer`, `ScriptRecovery`, `DisplayMath` and `InkMap`.
  - It is off unless `OCR_PROFILE=1`.
  - Experiments sit behind `OCR_EXP_{DRYRUN,MEMO,SHORTCUT,NOQR,NOSHAKY,READFAST}`.
  - Example from `tools/ocr-bench`:
    `OCR_PROFILE=1 OCR_EXP_DRYRUN=1 OCR_EXP_MEMO=1 ./.build/release/ocr-bench run`, then
    `python3 runs-prev/stats.py prof out/results.json` for the stage table, and
    `python3 runs/speedtab.py A.json B.json` for the on/off tables.
  - None of this is for merge.
- **Continuity:** A previous reviewer (worktree `agent-a38b2ea16b5cb9670`, same commit) wrote the W
  cases, the instrumentation, the as-shipped debug and release runs, the DRYRUN/NOQR/NOSHAKY/READFAST
  experiments and the batching micro-benchmark. This review copied them in
  (`tools/ocr-bench/runs-prev/`) and re-ran the gated profile. It reproduced within 2 % per case
  (median ratio 1.02), with identical outputs, so the earlier data is valid. New in this review: the
  cold/idle/warm-up measurements (`runs/cold.txt`, `runs/idle.txt`), the duplicate-read count, the memo
  and shortcut experiments (`runs/gate-memo.json`, `runs/gate-memo-short.json`), the root causes of the W
  errors, and the ranking.
- **Harness:** `tools/ocr-bench` renders each case offscreen (WKWebView, never shown) and calls the real
  `TextRecognizer.recognize(in:pointWidth:math:)`. Commands:
  `./.build/release/ocr-bench run [--no-math] [--rawvision]`, `OCR_PROFILE=1` for stage timing, and
  `OCR_REPEAT=N` to keep the fastest of N.
- **Machine and noise:** the owner's M3 MacBook, with other sessions active (load average about 4). Per
  case, a repeated run differs by −15 %…+6 % (p10…p90). Treat single-case numbers as ±10–15 %; the area
  medians are stable.
- **Not measured:**
  - The full app path: screen grab, the selection overlay and the clipboard write add on top.
  - Intel or 8 GB machines.
  - Debug timings for the 30 W cases (the debug run predates them).
  - Live Text on the W cases.
- **W-case scope:** 30 synthetic renders (fonts through WebKit, 1× via downscaling) are a sample, not
  a benchmark of real screenshots. Each accuracy score rests on a few cases per area. The prose-damage
  findings are backed by an explained root cause, not only by the count.
