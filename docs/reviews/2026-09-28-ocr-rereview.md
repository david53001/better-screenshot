# Capture Text (OCR) re-review — 2026-09-28

**Overall: 4/10** — "Good, with noticeable issues", at the low end. The pipeline is now much better
than raw Apple Vision or macOS Live Text at rebuilding **structure**:
- Tables come out as tab-separated rows.
- Code keeps its indentation and blank lines.
- Wrapped paragraphs rejoin, and two-column pages come out in reading order.

On the 66-case corpus it was tuned on it passes 36/66 (mean CER 0.058, versus Live Text's 0.18).
On 35 new held-out cases it passes **2/35** (mean CER 0.177, versus Live Text 0.20 and raw Vision
0.27). Two things keep it below 6:
- **Math still fails on common inputs** (0/13 held-out). Integrals, sums, limits and inline
  fractions come out scrambled. Many other formulas change meaning: `log₂32` → `log232`,
  `2 sin²θ` → `2 sin⁻ 0`, `3x²` → `322`, ionic charges lost.
- **The new math layer damages ordinary text it wasn't tuned on.**
  - It silently rewrites characters: `−2.1%` → `-2.1⁰/o` in a spreadsheet, `5,140` → `5,¹40` in a
    bold Georgia table, "the 3rd of March." → `the 3ʳᵈ/1_OfMarch.`, and `"node --test"` →
    `"T_(IO)de --testⁱr` in JSON.
  - It classifies chemistry and log sentences as source code, which throws away the superscripts it
    had just recovered.

Of the 35 held-out cases, 11 contain damage the pipeline itself introduced. A user cannot trust a
paste without proofreading it, and that is what holds the score at 4 rather than 5–6.

**Standard:** the clipboard holds what a careful human would retype on the first try (see
Calibration) · **Method:** existing corpus (66) + held-out (35) + 6 no-harm probes + code analysis
+ Vision-free probes · **Reviewer:** independent subagent (did not build the feature)

## Calibration

- **What it is:** BetterScreenshot is a free, local macOS clone of CleanShot X (a native Swift
  menu-bar app for macOS 14+, built with SwiftPM, no Xcode). **Capture Text** (⌘⇧7) works like this:
  1. The user drags a screen region.
  2. The pixels go to Apple **Vision** (`VNRecognizeTextRequest`, on-device OCR, "accurate" level,
     language correction on, languages from the user's preferences — `en-US` + `ro-RO` here), plus
     QR detection.
  3. The recognized lines are rebuilt into text and put on the clipboard.

  The entry point is `TextRecognizer.recognize(in:pointWidth:)` in
  `Packages/CaptureKit/Sources/CaptureKit/TextRecognizer.swift`, called from
  `App/Capture/CaptureCoordinator.swift` `runCaptureText`. It is followed by:
  - `ScriptRecovery` + `InkMap`: detect super/subscripts, √, ±, ≠ and inline fractions from the pixels.
  - `TextReflow`: lines → paragraphs, tables, code, lists, reading order.
  - `MathLayout`: stacked fractions and detached exponents.
  - `Homoglyphs`: Cyrillic/Greek look-alikes → Latin.
- **Audience:** the owner (an IB — International Baccalaureate — high-school student) and general users. They capture slides,
  PDFs/textbooks, worksheets and **math**, web articles, code, tables, UI screenshots and video
  frames, then paste into Docs, Notes, AI chats, code editors and spreadsheets.
- **Maturity:** a personal tool with tagged releases, so it is expected to feel finished.
  **Constraint:** fully local, never any cloud OCR.
- **Math format (owner decision):** readable Unicode, not LaTeX — `x² + y² = z²`, `xᵢ`,
  `(a + b)/2`, `√(x + 1)`, `∫₀¹ f(x) dx`, `∑ᵢ₌₁ⁿ i`, Greek, `≤ ≥ ≠ ± × ÷ → ∞ ∈`. `^(…)`/`_(…)` is
  used only where Unicode has no glyph. Flattening `x²` → `x2` is **wrong**.
- **A 10:** exact characters; paragraphs rebuilt; headings on their own line; lists one item per
  line with markers and nesting; code line-per-line with indentation; tables one row per line with
  **tab**-separated cells; multi-column text in reading order; math as readable Unicode. At least as
  good as CleanShot X and macOS Live Text.
- **Anchors:**
  - **3:** a common input (textbook equation, simple table, two-column page) comes out scrambled or
    meaning-changed.
  - **6:** prose, lists and code paste correctly; math and tables lose structure that can be fixed
    by hand in under a minute.
  - **9:** everything pastes correctly first try, apart from rare glyph-level misreads Live Text also
    makes.
- **Scale:** 8–10 basically perfect · 4–7 great/good with noticeable issues · 1–3 not to our
  standard.
- **Severities:**
  - **High:** meaning changes, content lost or scrambled, or the user must retype.
  - **Medium:** noticeable cleanup.
  - **Low:** rare or cosmetic.

  An area with a High issue cannot score 8+.
- **Terms:**
  - **CER** (character error rate) = edit distance ÷ expected length; 0 = perfect.
  - **Pass** = the normalized clipboard exactly equals an accepted ground truth.
  - **Raw Vision** = Vision's own lines, in Vision's order, one per line, with no rebuilding.
  - **Live Text** = macOS's built-in "copy text from image" (VisionKit), run on the same image.
  - **Pipeline-introduced** = the error is not in raw Vision's output; our code added it.

## Scoreboard

The existing corpus has 66 cases; the held-out set has 35 new cases. Existing-case scores prove
little, because the code was tuned on those 66 cases. **Held-out results carry more weight.**

| Area | Score | Existing pass / CER | Held-out pass / CER | Verdict |
|---|---|---|---|---|
| 1. Prose & paragraphs | **6/10** | 4/6 · 0.001 | 0/5 · 0.026 | Paragraphs and headings right; superscript ordinals corrupt a line; two short paragraphs can merge |
| 2. Lists | **6/10** | 4/6 · 0.009 | 0/1 · 0.008 | Bullets, numbers and 3-level nesting right; IB `(ii)`/`(iii)` sub-parts lose their nesting |
| 3. Code | **5/10** | 1/8 · 0.011 | 0/4 · 0.063 | Indentation, blank lines and gutters handled well; terminal output and 1× JSON collapse into paragraphs |
| 4. Tables | **5/10** | 5/7 · 0.005 | 1/4 · 0.108 | Tab-separated grids far better than Live Text; numbers in cells can be silently rewritten (`%`, bold digits) |
| 5. Math | **3/10** | 8/22 · 0.161 | 0/13 · 0.276 | Simple `x²`, `H₂O` and stacked fractions work; display math, inline fractions and θ/π/′ are scrambled or meaning-changed |
| 6. Layout & reading order | **5/10** | 6/8 · 0.003 | 1/5 · 0.144 | Columns, sidebars, dialogs and slides good; settings window with a sidebar interleaved into its rows |
| 7. Robustness | **6/10** | 8/9 · 0.006 | 0/3 · 0.351 | Dark mode, colours, QR and empty regions fine; 1× small capitals lose Ș/Ț; legible math can return "No text found" |
| 8. No-harm | **3/10** | 1/66 cases damaged | **11/35 cases damaged** | Plain prose is safe; anything with scripts, `%`, bold old-style digits or JSON can be silently corrupted |
| 9. Pipeline code quality | **4/10** | 161/161 unit tests pass | 3/3 synthetic probes confirm root causes | Readable, fast (release median 80 ms); overfit heuristics, no guard on rewritten text, code detection too eager |
| **Overall** | **4/10** | **36/66 · 0.058** | **2/35 · 0.177** | Big structural gains; math and trust (no silent corruption) not there yet |

Baselines on the same images:

| Set | BetterScreenshot | Live Text | Raw Vision | Ours better / worse than Live Text | Ours worse than raw |
|---|---|---|---|---|---|
| Existing 66 | 36 pass · 0.058 | 14 · 0.182 | 5 · 0.237 | 44 better / 1 worse | 0 |
| Held-out 35 | 2 pass · 0.177 | 0 · 0.200 | 0 · 0.268 | 20 better / 9 worse | 6 (H02 H15 H18 H21 H23 H34) |

Held-out per area (ours / Live Text / raw CER):
- prose 0.026 / 0.015 / 0.020
- lists 0.008 / 0.029 / 0.025
- code 0.063 / 0.120 / 0.090
- tables 0.108 / 0.137 / 0.736
- math 0.276 / 0.321 / 0.328
- layout 0.144 / 0.142 / 0.168
- robustness 0.351 / 0.344 / 0.346 (dominated by H35, see §7)

Evidence images (image, expected, our clipboard and Live Text side by side) are in
`docs/reviews/2026-09-28-ocr-rereview/`:
- `01-math-heldout.jpg`: H02 H03 H10 H13
- `02-noharm-corruption.jpg`: H18 H24 H25
- `03-code-terminal-json.jpg`: H21 H23
- `04-math-display.jpg`: H01 H11 M08 M09
- `05-layout-sidebar.jpg`: H30 H15
- `06-tables-good.jpg`: H26 H24

## 1. Prose & paragraphs — 6/10

**Works well**
- Wrapped lines rejoin into one line per paragraph, and headings stay on their own line: P01, P02,
  P04, P06 (first-line-indent book style), R01, R02, R05, R06.
- The same holds in held-out H14, H16 and H17, whose remaining errors are Vision glyph misreads.
- A centred, wrapped dialog message is rejoined correctly (H28).
- Plain digits, percentages, apostrophes and possessives are untouched (N01, N02, N06).
- On existing prose it matches Live Text (CER 0.001 vs 0.002) and beats raw Vision (0.010).

| # | Severity | Case(s) | Expected → Actual | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| P1 | High | H18 | `…published on the 3rd of March.` → `…published on`⏎`the 3ʳᵈ/1_OfMarch.` | Word and Google Docs superscript ordinals by default, so this is a common input. Words get destroyed and the paragraph splits. Live Text gets it right (CER 0.009 vs our 0.083). | `ScriptRecovery.recover` rewrote Vision's correct `of March.` line (confirmed by probe). Add the output guard in Top fix 1 (`ScriptRecovery.swift:87-92`). The split comes from P3. |
| P2 | Medium | H15 | two paragraphs (10 px apart) → one line `…iced tea. The new ThinkPad™…` | Separate paragraphs glued together. Raw Vision had them apart. | `TextReflow.continues` checks line pitch only once the paragraph has ≥2 lines (`TextReflow.swift:516-519`). A one-line first paragraph falls through to the right-edge fit test. Compare against the median pitch of the whole column/run too. |
| P3 | Medium | H07, H18, synthetic probe (a) | a wrapped line containing any super/subscript glyph is not rejoined: `…reaches 4.5`⏎`× 10⁵ J.` | The paragraph breaks mid-sentence whenever a unit or exponent lands on the next line. The probe showed the same text with `1030` joins and with `10³⁰` splits. | `wrapped()` refuses to join when `isMath` is true (`TextReflow.swift:541`). `isMath` (`MathLayout.swift:122-124`) is true for any line with a script glyph and ≤1 long word. Use it only for short, isolated display lines, or run the fit test first. |
| P4 | Medium | H34 | `money —`⏎`someone else did.` → `money someone else did.` | A spaced dash is deleted, as if it were a soft hyphen. | `joinWrapped` removes any trailing `-` before a lowercase word (`TextReflow.swift:612`). Require a letter immediately before the hyphen (`[\p{L}]-$`). |
| P5 | Low | P03 | `light-dependent` (real hyphen at a line break) → `lightdependent` | Compound words lose their hyphen. Live Text keeps it. | Same place: keep the hyphen when the joined word isn't in a dictionary, or when both halves are words. |
| P6 | Low (Vision) | H14, H17, H15 | footnote `¹` → `'`; `Ioana` → `loana`; `3×` → `3x`; `B0.12` → `B0. 12` | Glyph misreads. Live Text makes the same ones. | The footnote case could be recovered: a raised `'` sitting right after a word end, at digit height, is `¹` (`ScriptRecovery.swift:267-272` currently forces narrow raised glyphs to punctuation). |

**Why 6:** prose usually pastes correctly (the anchor for 6). But P1 is a High on a common input,
and P2–P4 are noticeable cleanup.

## 2. Lists — 6/10

**Works well**
- Bullet glyphs are normalized, numbered items kept and wrapped items rejoined (L01, L02).
- Three-level nesting comes out as tabs (L03).
- IB right-aligned marks join their item with a tab (L04, H13).
- `1.` / `(a)` / `(i)` levels are all correct in H19.

| # | Severity | Case(s) | Expected → Actual | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| L1 | Medium | H19 | `⇥⇥(ii) Hence find…` → `(ii) Hence find…` (nesting lost) | IB papers use (i)/(ii)/(iii)/(iv) everywhere; the item looks like it belongs to the top level. | The `listMarker` regex only allows one letter (`TextReflow.swift:596-597`). Add roman numerals: `\(?(?:[ivx]{1,4}\|[IVX]{1,4})[.)]`. |
| L2 | Low (Vision) | L05, L06 | `☐`/`☑` → `•`; `–` → `-` | Checklist state is lost. | Vision reads the box as a bullet. The pipeline could check the ink (hollow square vs filled) before normalizing. |

**Why 6:** flat and nested lists are right. The one Medium hits the owner's most common list shape.
Held-out evidence is thin (1 case).

## 3. Code — 5/10

**Works well**
- Indentation is rebuilt from pixel geometry, and blank lines are kept (C01–C07; held-out H20, H22
  exact structure).
- Gutter line numbers are dropped even when they don't start at 1 (C05, H22).
- Code lines are re-read without language correction, which fixes `items. reduce (` →
  `items.reduce(`, and `‹›` → `<>`.
- Existing code CER is 0.011 versus Live Text 0.096.

| # | Severity | Case(s) | Expected → Actual | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| K1 | High | H21 | a 6-line terminal session (custom prompt `~/ib-ia $`, `git log` output) → 2 long lines: `~/ib-ia $ git log --oneline -3 alb2c3d Fix off-by-one in parser 9f8e7d6 …` | Terminal output is scrambled into prose. Raw Vision had it line-per-line. | The prompt signal only matches `$ ` at line start (`TextReflow.swift:434`), and `git log` lines carry no code signal. Match `^\S*[$#%>] ` (`~/dir $`, `user@host:~$`, `PS C:\>`). Make a monospaced run that contains a prompt line code as a whole — the merge rule at `TextReflow.swift:396-407` only adopts short blocks next to code. |
| K2 | High | H23 (1×) | `"test": "node --test",` → `"test": "T_(IO)de --testⁱr`; lines merged 2–4 per line; `{` `}` lines lost | A JSON config comes out corrupt and unparseable. | (1) ScriptRecovery runs on every line **before** code classification (`TextRecognizer.swift:24-41`) and corrupted the line (Top fix 1). (2) The corrupted text changes `charWidth` (`TextReflow.swift:70`), so `isMonospace` (`:448-452`) fails and the block becomes prose. (3) Quoted JSON keys match no code signal (`:439` only matches bare `key:`). Classify from Vision's original text/raw read, and add a `^\s*"[^"]+":` signal. |
| K3 | Medium (Vision + pipeline) | C01, C03, H23 | a line holding only `}` or `{` is missing (C03 also leaves a blank line where the `}` was) | Code no longer balances, so it has to be fixed by hand. | Vision rarely returns single-glyph lines. When indentation steps back out with no closer, re-read that row's ink (as `rereadBlobs` does for fractions). At least don't emit a blank line (`TextReflow.swift:470-473`). |
| K4 | Low (Vision) | C01, C07, C04, H20, H22 | `{`→`i`, `[`→`L`, `main.py`→`main-py`, `COUNT(*)`→`COUNT (*)`, `s.name`→`S.name`, `"""`→`''"` | Token-level fixes needed. | Some are fixable in `cleanedCode` (`TextReflow.swift:484-490`): `WORD (` → `WORD(` in code, and `''"` → `"""`. |

**Why 5:** structure reconstruction is genuinely good (the main job). Two held-out cases (a
terminal session, a JSON file) come out scrambled or corrupted — both common captures.

## 4. Tables — 5/10

**Works well**
- Real tab-separated rows with the header on its own line (T01, T02, T05, T06, H26).
- Empty cells keep their tab (T02, T04, H26), and wrapped cells are joined (T04, T06).
- Borderless and dark-mode tables work (T05, H25 structure, H26).
- Live Text passes 0/11 tables because it emits one cell per line.

| # | Severity | Case(s) | Expected → Actual | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| T1 | High | H24 | `South ⇥ … ⇥ −2.1%` → `… ⇥ -2.1⁰/o` | A number is silently changed in data pasted into a spreadsheet. Raw Vision read `-2.1%` correctly. | ScriptRecovery treats the `%` rings as a raised `0` and a lowered `o` (confirmed by probe: `"-2.1%"` → `"-2.1⁰/o"`). Skip glyphs that form a `%` (two small rings with a diagonal between them) in `classify` (`ScriptRecovery.swift:195-224`); Top fix 1's guard also rejects this. |
| T2 | High | H25 | `Gross profit ⇥ 5,140 ⇥ 4,140` → `5,¹40 ⇥ 4,¹40` | Numbers in a financial table are silently wrong. Bold Georgia rows only; regular Georgia prose was fine (N01). | Georgia's old-style `1` is x-height, and the descending `4`/`5` pull the baseline down. A script digit followed by a full-size digit (`5,¹40`) is never real — reject it. Measure digits against other digits, not against `capHeight` (`ScriptRecovery.swift:178-191`, `:218`). |
| T3 | Medium | H24 | merged title `Q3 Sales by Region` → pasted **after** the table | The title ends up under the data. Live Text keeps it on top. | Pieces are sorted by Vision's order (`TextReflow.swift:97, 102`), and Vision listed the title in the middle of its column-major read. Order pieces that lie fully above a grid by y. |
| T4 | Medium (Vision) | H27, T07 | single-glyph cells `ρ`, `v`, `p` dropped → empty cells; `Q` → `2` | A column of symbols is lost. | Vision skips lone glyphs. For an empty cell that contains ink, re-read it with a context prefix (the `rereadBlobs` trick, `ScriptRecovery.swift:346-376`). |
| T5 | Low (Vision) | H25, T03, H27 | header `2023` missing; `Ana lonescu`; `kg m⁻³` → `kgm⁻³` | Minor cleanup. | — |

**Why 5:** grid reconstruction is the strongest part of the pipeline. But silently changed
numbers (T1, T2) are exactly what spreadsheet users can't tolerate.

## 5. Math — 3/10

**Works well**
- Single superscripts/subscripts where Vision reads the base: M01 `E = mc²`, M02, M14 `m/s²`,
  `10⁻³`, M22, H12 `ax²`/`b²`, H32 `m s⁻²`, H09 line 1 `e⁻ˣ²`.
- Chemistry subscripts in HTML: M13 `H₂O`, `CO₂`.
- Stacked fractions with the bar detected from the pixels: M04 quadratic formula, M05, M21
  `(1 + r/n)ⁿᵗ`, H05 `P(A∩B)/P(B)`.
- Single radicals: M07 line 1 `√(x+1)`.

These beat Live Text everywhere (it passes 0/35 math cases).

| # | Severity | Case(s) | Expected → Actual | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| M1 | High | M08, M09, M20, H04, H11, M12, H01 | `∫₀¹ x² dx = 1/3` → `1`⏎`x² dx =.`⏎`1`; `∑ᵢ₌₁ⁿ i = …` → `Zi=n(n + 1)2`⏎`i = 1`; `f′(x) = lim_(h→0) …` → `f (x) = limf(x+h)-f(x)`⏎`h→ 0⇥h`; `∫ x³ dx = x⁴/4 + C` → `/x³ dx=X/4 4• + C`; `S∞ = u₁/(1 − r)` → `Soo = "LT r < l` | Integrals, sums, limits, matrices and sequences — the core of IB math — must be retyped. | There is no handling for big operators with limits above/below. Treat `∫`/`∑`/`lim` glyphs (tall, or `Z`/`/` read by Vision) as anchors, and attach the small lines stacked over and under them as limits, the way `stackingFractions` does for bars (`MathLayout.swift:13-39`). |
| M2 | High | H02, H08, H11; probe (b) | `log₂32 = 5` → `log232 = 5`; `SO₄²⁻`, `Fe³⁺`, `OH⁻` → `SO4=`, `Fe3t`, `3OH` | Meaning changes. ScriptRecovery **had** recovered `logₐ`, `e³`, `SO₄²⁻`, `Fe³⁺` (probe), but the block was classified as **code**. Code uses the correction-off re-read (`rawText`), so all of it was thrown away — and `logay` became `Iogay`. | The function-call signal `\b[A-Za-z_]\w+\(` matches `loga(`, `Fe(`, `iron(III)` (`TextReflow.swift:435`). A single line with one hit is code (`:456`). Require monospace for code unless a strong signal is present (`;`/`{`/prompt/keyword). Keep recovered scripts for lines whose raw read lacks them (`TextRecognizer.swift:46-55`, `TextReflow.swift:475`). |
| M3 | High | H10 | `1 − 3/10 = 7/10` → `13/1037/103`; `3/10,` → `3/10o` | Inline fractions in a sentence come out scrambled into a wrong number. | The inline-fraction path drops the operators between fractions. After `glyphTexts` builds fraction pieces (`ScriptRecovery.swift:313-320`), keep the glyphs between them, and reject a result that loses `=`/`−` Vision had read. |
| M4 | High | H03, H07, N04 | `2 sin²θ` → `2 sin⁻ 0` (reads as inverse sine); `m s⁻²` → `m s⁼²`; `(CO₂)` → `(CO_z)` | The pipeline **amplifies** Vision's misread of `²` into wrong notation that looks authoritative. | `=` and `-` count as scriptable (`ScriptRecovery.swift:529-531`), so a misread is scripted instead of re-read. `z` isn't in the "descender explains the drop" set (`:276-277`). Treat a lone raised `-`/`=` next to a digit, and a lowered `z`, as misreads that need the re-read. |
| M5 | High (Vision, unrepaired) | M17, H03, M03, M11, M15, H13, H12 | `θ` → `0`; `π` → `n`; `≠`/`±` → `‡`; `∈` → `E`; `f′(x)` → `f(x)`; `3x²` → `322`; `Δ` → `A` | Meaning changes. The `‡` → `≠/±` repair exists (`ScriptRecovery.swift:303`) but only runs when glyphs and characters align one-to-one; M11's long line falls back to all-or-nothing (`:75-86`) and skips it. | Map characters to glyphs with Vision's per-character boxes (`VNRecognizedText.boundingBox(for:)`) instead of gap-count segmentation (`segment`, `:241-251`), so symbol repairs work on long lines. A prime is a small raised stroke after `f` — detect it like a script. |
| M6 | High (Vision) | M10, H06 | a legible formula → "No text found" (clipboard untouched) | Content lost entirely. Live Text also fails. | Out of the pipeline's control, but the HUD (the small on-screen confirmation message) could say "No text found — try a larger selection". Retrying with correction off gives some text for M10. |

**Why 3:** textbook equations come out scrambled or meaning-changed — the calibration's anchor for
3. That held on 13/13 held-out math cases and 14/22 existing ones.

## 6. Layout & reading order — 5/10

**Works well**
- Two- and three-column articles in reading order, with a paragraph joined across the column break
  (Y01, Y02).
- Main text + boxed sidebar (Y03), and a figure with no text (Y04).
- Running header with the page number after a tab (Y05), and form labels with their values (Y06).
- Slides with two bullet columns (Y07), chat bubbles (Y08), a macOS alert dialog (H28 pass), and a
  slide with a formula (H32).
- H31 (a two-column lab report) has every paragraph correct and joined.

| # | Severity | Case(s) | Expected → Actual | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| Y1 | High | H30 | sidebar list + settings rows → `General⇥Appearance`, `Wi-Fi⇥Appearance⇥Auto`, `Bluetooth⇥Accent colour⇥Multicolour`, `⇥Show scroll bars⇥When scrolling` | A settings screenshot comes out scrambled: sidebar items become cells of unrelated rows. Raw Vision listed the sidebar first, then the pane. | `grids()` groups any vertically overlapping pieces into rows (`TextReflow.swift:192-233`). Split a grid when one column band's rows are evenly spaced on their own pitch while the others follow a different one, or when a band is separated by a large empty gutter / background change. |
| Y2 | Medium (Vision order) | H31 | the figure caption comes out last instead of after the first paragraph | The caption is detached from its place. | Vision's order is kept as-is. The pipeline could order pieces within a column by y. |
| Y3 | Medium (Vision) | H29 | context-menu shortcuts `⌘Z`, `⌘X`, … lost; `⌘A` → `HA` | Keyboard shortcuts are lost from menu captures. | Vision can't read ⌘ ⌥ ⇧. Out of scope unless handled with glyph templates. |
| Y4 | Low (Vision) | H32, Y05, Y06, R03 | `F = ma` → `F= ma`; `·` → `•`; checkbox → `•` | Cosmetic. | — |

**Why 5:** reading order is now right for articles and slides (a big change since the last
review). A common UI layout still comes out scrambled.

## 7. Robustness — 6/10

**Works well**
- Dark mode (R01, H26), gradient banner (R03), coloured backgrounds and low-contrast grey text
  (R04).
- Romanian diacritics at 2× (R05), German/French/Spanish accents (R06).
- A dominant QR code wins, and a small poster QR is appended to the text (R07, R08).
- An empty gradient gives "No text found" (R09), and 1× small text works (R02, P04).
- An outlined subtitle on a video frame is recognized (H34, apart from the dash).

| # | Severity | Case(s) | Expected → Actual | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| R1 | Medium (Vision) | H33 (1×, Verdana 12) | `„Ștefan…”`, `Țara` → `„Stefan…"`, `Tara` | Romanian capitals lose their comma-below on external monitors. Live Text keeps `Ș`. | Try a 3× upscale for small text (`TextRecognizer.upscaleFactor`, `TextRecognizer.swift:130-133`), or re-read uppercase S/T at line start with an ink check below the glyph. |
| R2 | Medium | M10, H06 | legible math → "No text found" | See M6. | — |
| R3 | Medium | H34 | spaced dash deleted | See P4. | — |
| R4 | Low (Vision) | H35 | an icon-only toolbar → `-O-` (Live Text also returns text) | A stray paste. | A single short line of symbols with no letters could be treated as no text. |
| R5 | Low | H07, H23, M19 | 1× captures have more errors: `2X` for `2x`, `3x?`, JSON corruption | Needs cleanup. | See K2 and M4. |

**Why 6:** it is robust across the visual conditions tested. The misses are mostly Vision's, plus
small-capital diacritics that matter to this owner.

## 8. No-harm — 3/10

"No-harm" asks: does the math/table/code logic ever damage ordinary text? Each finding below was
checked against raw Vision, so it is **pipeline-introduced**.

**Works well**
- Plain prose paragraphs, digits, percentages in prose, apostrophes, possessives and contractions
  pass through untouched: N01, N02, N06, H14, H16, H17 (their remaining errors are Vision's).
- Capital letters next to a superscript are not wrongly lowercased (H16 `Section C`, `OXO`, `SOS`,
  `Table X` all intact).
- On the existing corpus only P03's hyphen was damaged.

| # | Severity | Case(s) | Damage the pipeline added (raw Vision was right) | Cause (file:line) |
|---|---|---|---|---|
| H1 | High | H18 | `of March.` → `/1_OfMarch.`; `the 3rd` → `the 3ʳᵈ/` | `ScriptRecovery.recover`: all-or-nothing fallback + re-read of the whole line with no plausibility check (`ScriptRecovery.swift:75-92`) |
| H2 | High | H24 | `-2.1%` → `-2.1⁰/o` | `%` rings classified as scripts (`ScriptRecovery.swift:195-224`) |
| H3 | High | H25 | `5,140` → `5,¹40`, `4,140` → `4,¹40` | Old-style digits vs `capHeight`/baseline (`ScriptRecovery.swift:178-191, 218`) |
| H4 | High | H23 | `"node --test",` → `"T_(IO)de --testⁱr` | ScriptRecovery runs on code before classification (`TextRecognizer.swift:24-41`) |
| H5 | High | H02 | correct `logay` → `Iogay`, plus recovered scripts discarded | Math misclassified as code → correction-off text used (`TextReflow.swift:435, 456, 475`; `TextRecognizer.swift:46-55`) |
| H6 | Medium | H21 | terminal lines merged into two paragraphs | Code not detected (`TextReflow.swift:434`) |
| H7 | Medium | H30 | sidebar items interleaved into rows | Over-eager grid (`TextReflow.swift:192-233`) |
| H8 | Medium | H15 | two paragraphs merged | Pitch check skipped for a one-line paragraph (`TextReflow.swift:516`) |
| H9 | Medium | H34 | ` —` deleted | Dehyphenation (`TextReflow.swift:612`) |
| H10 | Medium | H03, H07, N04 | `sin-` → `sin⁻`, `s=2` → `s⁼²`, `COz` → `CO_z` | Misreads scripted instead of re-read (`ScriptRecovery.swift:276-277, 529-531`) |
| H11 | Low (code risk, not observed) | N03 | Vision itself read `A0`/`B0` as `AO`/`BO`, so the rule never fired | The chemistry rule `0` → `O` (`ScriptRecovery.swift:307-309`) applies to the **whole line** when word segmentation falls back to one group. It could turn a correctly read `A0`, `B0` or `Room 0` into `O` in any line that also holds a subscript. |

**Why 3:** 11/35 held-out cases contain text the pipeline broke, 5 of them by silently rewriting
characters in non-math text. A clipboard tool that sometimes changes numbers and words without any
signal is "not to our standard", even though plain prose is safe.

## 9. Pipeline code quality — 4/10

**Works well**
- Clear layering: pure, Vision-free geometry in `TextReflow` (testable with synthetic lines),
  pixel analysis isolated in `InkMap`/`ScriptRecovery`, and a tiny `RecognitionResolver`.
- Comments explain the why.
- `swift run --package-path Packages/CaptureKit CaptureKitTests` → **161/161 pass**.
- The `tools/ocr-bench` harness makes changes measurable.
- **Fast:** release build median 80 ms per capture, p90 (90th percentile) 146 ms, max 270 ms (H23), measured over all
  107 cases.

| # | Severity | Where | Issue | Fix |
|---|---|---|---|---|
| Q1 | High | `TextRecognizer.swift:24-55`, `TextReflow.swift:475` | Order-of-operations coupling. ScriptRecovery rewrites every line; classification then runs on the rewritten text (its `charWidth` changes, `TextReflow.swift:70`); a code block then discards the rewrite in favour of a separate correction-off read. One misclassification flips the output in two ways (M2, K2). | Classify from Vision's original text and geometry. Run ScriptRecovery only on non-code blocks. Store the recovered text in a separate field instead of overwriting `text`. |
| Q2 | High | `ScriptRecovery.swift:75-92` | There is no guard on `recover()` output. When word segmentation fails, the whole line is re-read as one group and any same-length result is accepted, which produces `/1_Of` and `T_(IO)de`. | See Top fix 1: accept a rewrite only if every non-script position still matches Vision's character (or is a known symbol repair). |
| Q3 | High | `TextReflow.swift:431-458` | The code signals are too broad for math/chemistry (`loga(`, `Fe(`) and too narrow for terminals/JSON (prompts other than `$ `, quoted keys). A single hit on a one-line block = code. | Weight signals; require monospace for weak signals; add prompt and JSON signals. |
| Q4 | Medium | `MathLayout.swift:122-124` used by `TextReflow.swift:541, 579` | `isMath` is a loose heuristic (any script glyph + ≤1 long word) that controls paragraph joining. | Restrict it to short, isolated lines, or drop it from `wrapped()`. |
| Q5 | Medium | `ScriptRecoveryTests.swift` (58 lines) | `recover()`, the source of every corruption above, has no direct test; only primitives (`script`, `classify` on synthetic boxes, `segment`, `align`) are tested. The harness corpus was used for tuning, and several constants cite one measured slide (`TextReflow.swift:38-41`), which suggests overfitting. The held-out gap (36/66 → 2/35) confirms it. | Commit the held-out cases as a regression set that is **not** tuned against. Add image-based unit tests for recover's refusal paths (`%`, old-style digits, a plain lowercase word). |
| Q6 | Low | `TextRecognizer.swift:32-38` | The "absorb" step drops any ≤4-character line within 0.3 line-heights whose script form appears as a substring of a recovered line. That could delete a legitimate short line (e.g. a `2` next to a line containing `²`). Not observed. | Require the absorbed box to sit raised or lowered relative to the line. |

**Why 4:** well-structured and fast, but with three High design flaws that directly cause the
silent corruptions, and tests that can't see them.

## Cross-cutting issues

1. **Overfitting.** Existing corpus 36/66; held-out 2/35. The structure gains (tables, code
   indentation, reading order) mostly generalize: held-out tables CER 0.108 vs Live Text 0.137, code
   0.063 vs 0.120. The math/script layer mostly does not: held-out math 0.276, only slightly better
   than Live Text's 0.321. That layer also creates new failure modes on non-math text.
2. **Rewrites without verification.** ScriptRecovery overwrites Vision's text. When its assumptions
   fail (a `%` sign, old-style digits, a split superscript ordinal, monospace code) the result is
   worse than doing nothing, and nothing checks that. Vision's text should be the default, with a
   rewrite accepted only when it is provably a superset (same base characters + scripts).
3. **Code/prose classification drives character output.** Classification decides whether the
   language-corrected or the uncorrected read is used, and whether recovered scripts survive. A
   classification error therefore becomes a character error (H02 `Iogay`).
4. **Vision limits the pipeline could route around.** Lone glyphs (`}`, `ρ`, `v`) are dropped, and
   ⌘/θ/π/′ are misread. The pipeline already has a re-read-with-context tool (`rereadBlobs`) that
   could be pointed at empty cells and missing closers.

## Top fixes (ranked by impact ÷ effort)

1. **Guard every ScriptRecovery rewrite (S).** In `ScriptRecovery.recover` (`ScriptRecovery.swift:87-92`),
   return the rewrite only if:
   - after mapping script characters back to their base forms (`²` → `2`, `ₐ` → `a`) and removing
     `√(`, `)`, `^(`, `_(`, `/` that it added, the characters equal Vision's (ignoring spaces), apart
     from positions flagged as symbol repairs (`‡`, `+` → `±`, `0` → `O`); and
   - no script digit is immediately followed by a full-size digit.

   Fixes H18, H23, H24 and H25 (4 High no-harm) and makes future tuning safe.
2. **Stop math/chemistry from being classified as code, and keep recovered scripts on the code path
   (S–M).**
   - Narrow the function-call signal (`TextReflow.swift:435`): ≥3-letter identifier, not a chemical
     formula `[A-Z][a-z]?\(`, not a known math function with a base.
   - Require `isMonospace` for weak signals (`:456-457`).
   - In `TextRecognizer.swift:46-55`, don't let `rawText` replace a line that ScriptRecovery changed.

   Fixes H02, H08, H11 and the chemistry-paragraph probe.
3. **Let wrapped lines with scripts rejoin (S).** Remove `isMath` from `wrapped()`
   (`TextReflow.swift:541`), or limit it to short centred lines. Fixes H07, the H18 split and probe (a).
4. **Cheap bundle (XS each):**
   - roman-numeral list markers (`TextReflow.swift:596-597`, H19);
   - dehyphenate only a letter-glued hyphen (`:612`, H34, and P03 with a dictionary check);
   - terminal prompts `^\S*[$#%>] ` plus a JSON-key signal (`:434-439`, H21, K2);
   - pitch check against the column for one-line paragraphs (`:516`, H15);
   - title-above-grid ordering (`:102`, H24).
5. **Big-operator math (M–L).** Stack limits over/under `∫`/`∑`/`lim` like fractions
   (`MathLayout.swift`). Map characters to glyphs with Vision's per-character boxes instead of
   gap-count segmentation, so `‡`, `′`, `θ` repairs work on long lines (`ScriptRecovery.swift:70-86`).
   This is the only route to math above 3.
6. Split sidebar + pane "grids" (`TextReflow.swift:204-233`, H30). Re-read empty table cells and
   missing code closers with the `rereadBlobs` context trick (T4, K3).

## Trend (vs `docs/reviews/2026-09-28-ocr-review.md`)

The earlier review (same day, same 66-case corpus, before the current tuning) scored **3/10 overall,
10/66 pass, CER 0.271**.

| Area | Earlier | Now | Change and why |
|---|---|---|---|
| Prose | 6 | 6 | Existing pass 2/6 → 4/6. Held-out found new issues: superscript ordinals, a merge, the dash. |
| Lists | 6 | 6 | Nesting and IB marks fixed (L03, L04 pass). Roman-numeral nesting still missing. |
| Code | 3 | 5 | Indentation and blank lines now rebuilt (existing CER 0.111 → 0.011). Held-out terminal and JSON cases fail. |
| Tables | 2 | 5 | Real tab-separated grids (existing CER 0.559 → 0.005). New: script recovery corrupts numbers. |
| Math | 2 | 3 | Existing 0/22 → 8/22. Held-out 0/13, and new meaning-changing amplification. |
| Layout | 2 | 5 | Reading order fixed (existing CER 0.322 → 0.003). Sidebar UI still scrambled. |
| Robustness | 7 | 6 | Poster-QR bug fixed (R08). Held-out found 1× Romanian capitals and "No text found" on legible math. |
| No-harm | — | 3 | New area. The math layer introduced silent corruption of non-math text. |
| Code quality | 3 | 4 | Earlier geometry bugs fixed. New coupling and unguarded rewrites. |
| **Overall** | **3** | **4** | Real progress on structure. Held-out testing shows the math gains don't generalize and add risk. |

On the corpus both reviews used, pass rate went 10/66 → 36/66 and CER 0.271 → 0.058, which is a
genuine improvement — the earlier review's structural High issues (reversed cells, lost indentation,
interleaved columns) are fixed. This review's lower-than-corpus verdict rests on the 35 held-out
cases, which the earlier review did not have.

## Harness & held-out cases (how to run, what was added)

- The harness is `tools/ocr-bench/` (see its `README.md`). It renders HTML cases offscreen with
  WKWebView (in a window that is never shown), runs the real `TextRecognizer.recognize`, and scores
  the clipboard string. Run from `tools/ocr-bench/`:
  - `./run.sh` builds and runs every case under a 300 s timeout guard (now **107** cases: 66 +
    35 held-out + 6 no-harm; the README still says 66).
  - Only the new cases:
    `./.build/debug/ocr-bench run --only $(seq -f "H%02g" 1 35 | tr '\n' ',' | sed 's/,$//') --livetext --rawvision --out out/mine`
    (add `N01,…` ids the same way for the no-harm probes; always keep the timeout guard shown below)
  - Timing: `swift build -c release`, then
    `(./.build/release/ocr-bench run --out out/rel > rel.log 2>&1 & PID=$!; (sleep 300; kill $PID) & wait $PID)`
  - `./.build/debug/ocr-bench dump H24` prints the raw Vision observations for a case.
- **Added:**
  - `tools/ocr-bench/Sources/ocr-bench/HeldOutCases.swift`, which defines:
    - `heldOut` (H01–H35): 13 math (IB sequences, log laws, trig with θ, integrals, P(A|B),
      vectors, physics units at 1×, ionic charges, e^(−x²), inline fractions, first-principles
      derivative, discriminant, exam question with marks); 5 prose look-alike traps; 1 nested
      IB list; 4 code (SQL, terminal, Python gutter from line 12, 1× JSON); 4 tables (merged title
      row, borderless financial, dark Notion-style, units with Greek); 5 layout/UI (alert, context
      menu, settings with sidebar, two-column report with figure, slide with formula); 3
      robustness (1× Romanian, video subtitle, icon-only toolbar).
    - `noHarm` (N01–N06): plain text aimed at specific rules.
  - `Cases.swift:6` now ends `+ heldOut + noHarm`.
  - Fonts used across the cases: Palatino, Verdana, Baskerville, Georgia, Times New Roman,
    Helvetica, Arial, SF, Source Code Pro, Monaco, Menlo, Courier New, STIX Two Math/Text.
  - Every rendered image was inspected before trusting a result. H05/H06/H09/H11 use
    `stretchy="false"` parentheses to avoid a WebKit artifact that textbooks don't have.
- **Outputs of this review** (git-ignored), in `tools/ocr-bench/out/rereview-2026-09-28/`:
  - `existing/`, `heldout/`, `noharm/` — each with `results.txt`/`.json`, including the Live Text
    and raw Vision baselines;
  - `release-all/` — all 107 cases, release build, with timings;
  - logs `run-*.log`, `dump*.log`.
- **Diagnostic probes** (not in the repo) were compiled from copies of the CaptureKit sources in a
  scratch directory, to call internal functions:
  - `ScriptRecovery.recover` per line, which located the H18/H24/H25/H08 rewrites;
  - `TextReflow.layout` block kinds, which showed H02/H08/H11 classified as `code` and H21 as
    `prose`;
  - synthetic `TextReflow.paragraphs` lines, which confirmed the `isMath` join break and the
    chemistry-paragraph → code misclassification.

## Method & limits

- All numbers are from runs in this session: debug build for the Live Text/raw comparisons, release
  build for timing. Results are deterministic (the existing-corpus run matched the developer's
  `run.log` exactly).
- Root causes were attributed by diffing each output against raw Vision's output for the same image.
  "(Vision)" marks errors already present in raw Vision.
- **Limits:**
  - Rendered HTML is cleaner than real screenshots, and PDFs rendered in Preview use different
    rasterization.
  - Math uses STIX Two (the only math font installed); textbooks set in Cambria Math or Computer
    Modern were not tested.
  - The held-out set is small per area (1 list case, 3–5 in several areas), so area scores lean on
    code analysis and the existing corpus.
  - Live Text is a stand-in for CleanShot X, which was not available to test.
  - Glyph-level Vision misreads are counted against the user experience but attributed to Vision
    where raw Vision shows them.
