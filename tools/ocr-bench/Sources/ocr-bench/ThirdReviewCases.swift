// Held-out cases for the third independent review (docs/reviews/2026-09-29-ocr-review.md).
// Written, with their ground truth, BEFORE any output for them was looked at. Deliberately
// different from Cases.swift / HeldOutCases.swift: fonts (Avenir, Avenir Next, Optima, Charter,
// Iowan Old Style, Hoefler Text, Gill Sans, Futura, Trebuchet, Tahoma, Seravek, PT Serif/Sans/Mono,
// Andale Mono, SF Mono, Comic Sans, Chalkboard SE), 1x vs 2x, dark mode, coloured/noisy
// backgrounds. Ground truth = what a careful human would retype (README.md conventions).
// V38–V44 are no-harm probes (plain text the math/code layers must leave alone).

private let stixV = "#cap{font-family:'STIX Two Text';font-size:30px} math[display=block]{margin:6px 0}"

/// Every combination of the accepted spellings of each slot.
private func vcombos(_ template: String, _ slots: [(String, [String])]) -> [String] {
    var out = [template]
    for (slot, options) in slots {
        out = out.flatMap { s -> [String] in
            guard s.contains(slot) else { return [s] }
            return options.map { s.replacingOccurrences(of: slot, with: $0) }
        }
    }
    return out
}

let thirdReview: [Case] = [
    // MARK: Math (11)

    Case(id: "V01", area: .math, desc: "IB functions: f(x) = 3(x − 2)² + 5 and its inverse with a root over a fraction", fit: true, css: stixV,
         html: #"""
         <math display="block"><mi>f</mi><mo stretchy="false">(</mo><mi>x</mi><mo stretchy="false">)</mo><mo>=</mo><mn>3</mn><msup><mrow><mo stretchy="false">(</mo><mi>x</mi><mo>−</mo><mn>2</mn><mo stretchy="false">)</mo></mrow><mn>2</mn></msup><mo>+</mo><mn>5</mn></math>
         <math display="block"><msup><mi>f</mi><mrow><mo>−</mo><mn>1</mn></mrow></msup><mo stretchy="false">(</mo><mi>x</mi><mo stretchy="false">)</mo><mo>=</mo><mn>2</mn><mo>+</mo><msqrt><mfrac><mrow><mi>x</mi><mo>−</mo><mn>5</mn></mrow><mn>3</mn></mfrac></msqrt></math>
         """#,
         expected: ["f(x) = 3(x − 2)² + 5\nf⁻¹(x) = 2 + √((x − 5)/3)"], mode: .ignoreSpaces),

    Case(id: "V02", area: .math, desc: "derivatives: stacked d/dx operator, 1/(x ln 2)", fit: true, css: stixV,
         html: #"""
         <math display="block"><mfrac><mi>d</mi><mrow><mi>d</mi><mi>x</mi></mrow></mfrac><mo stretchy="false">(</mo><mi>sin</mi><mn>3</mn><mi>x</mi><mo stretchy="false">)</mo><mo>=</mo><mn>3</mn><mi>cos</mi><mn>3</mn><mi>x</mi></math>
         <math display="block"><mfrac><mrow><mi>d</mi><mi>y</mi></mrow><mrow><mi>d</mi><mi>x</mi></mrow></mfrac><mo>=</mo><mfrac><mn>1</mn><mrow><mi>x</mi><mi>ln</mi><mn>2</mn></mrow></mfrac></math>
         """#,
         expected: ["d/dx(sin 3x) = 3cos 3x\ndy/dx = 1/(x ln 2)"], mode: .ignoreSpaces),

    Case(id: "V03", area: .math, desc: "log equation in a sentence (Charter 18, HTML sub/sup, italic x)", width: 820,
         css: "#cap{font-family:Charter;font-size:18px;line-height:1.7} p{margin:0}",
         html: #"<p>Solve log<sub>3</sub>(<i>x</i> + 1) + log<sub>3</sub>(<i>x</i> − 1) = 1, giving <i>x</i><sup>2</sup> − 1 = 3 and so <i>x</i> = 2.</p>"#,
         expected: ["Solve log₃(x + 1) + log₃(x − 1) = 1, giving x² − 1 = 3 and so x = 2."], mode: .ignoreSpaces),

    Case(id: "V04", area: .math, desc: "binomial distribution sentence: ~, ≤, ≈ (Avenir 17)", width: 700,
         css: "#cap{font-family:Avenir;font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>Let <i>X</i> ~ B(10, 0.4). Then E(<i>X</i>) = <i>np</i> = 4 and P(<i>X</i> ≤ 3) ≈ 0.382.</p>"#,
         expected: vcombos("Let X TIL B(10, 0.4). Then E(X) = np = 4 and P(X ≤ 3) ≈ 0.382.", [("TIL", ["~", "∼"])]), mode: .ignoreSpaces),

    Case(id: "V05", area: .math, desc: "definite integral with evaluation bracket [x² + x]₁³", fit: true, css: stixV,
         html: #"<math display="block"><msubsup><mo>∫</mo><mn>1</mn><mn>3</mn></msubsup><mo stretchy="false">(</mo><mn>2</mn><mi>x</mi><mo>+</mo><mn>1</mn><mo stretchy="false">)</mo><mspace width="0.2em"/><mi>d</mi><mi>x</mi><mo>=</mo><msubsup><mrow><mo>[</mo><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mi>x</mi><mo>]</mo></mrow><mn>1</mn><mn>3</mn></msubsup><mo>=</mo><mn>10</mn></math>"#,
         expected: ["∫₁³ (2x + 1) dx = [x² + x]₁³ = 10"], mode: .ignoreSpaces),

    Case(id: "V06", area: .math, desc: "sum of squares: ∑ with limits = n(n + 1)(2n + 1)/6", fit: true, css: stixV,
         html: #"<math display="block"><munderover><mo>∑</mo><mrow><mi>r</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><msup><mi>r</mi><mn>2</mn></msup><mo>=</mo><mfrac><mrow><mi>n</mi><mo stretchy="false">(</mo><mi>n</mi><mo>+</mo><mn>1</mn><mo stretchy="false">)</mo><mo stretchy="false">(</mo><mn>2</mn><mi>n</mi><mo>+</mo><mn>1</mn><mo stretchy="false">)</mo></mrow><mn>6</mn></mfrac></math>"#,
         expected: vcombos("SIGᵣ₌₁ⁿ r² = NUM/6", [("SIG", ["∑", "Σ"]), ("NUM", ["n(n + 1)(2n + 1)", "(n(n + 1)(2n + 1))"])]), mode: .ignoreSpaces),

    Case(id: "V07", area: .math, desc: "vectors: bold a, root of a sum of squares with (−1)², dot product", fit: true, css: stixV,
         html: #"""
         <math display="block"><mo stretchy="false">|</mo><mi mathvariant="bold">a</mi><mo stretchy="false">|</mo><mo>=</mo><msqrt><msup><mn>2</mn><mn>2</mn></msup><mo>+</mo><msup><mrow><mo stretchy="false">(</mo><mo>−</mo><mn>1</mn><mo stretchy="false">)</mo></mrow><mn>2</mn></msup><mo>+</mo><msup><mn>3</mn><mn>2</mn></msup></msqrt><mo>=</mo><msqrt><mn>14</mn></msqrt></math>
         <math display="block"><mi mathvariant="bold">a</mi><mo>·</mo><mi mathvariant="bold">b</mi><mo>=</mo><mo stretchy="false">|</mo><mi mathvariant="bold">a</mi><mo stretchy="false">|</mo><mo stretchy="false">|</mo><mi mathvariant="bold">b</mi><mo stretchy="false">|</mo><mi>cos</mi><mi>θ</mi></math>
         """#,
         expected: vcombos("|a| = √(2² + (−1)² + 3²) = √14\na DOT b = |a||b| cos θ", [("DOT", ["·", "⋅", "•"])]), mode: .ignoreSpaces),

    Case(id: "V08", area: .math, desc: "1x: trig equation sentence with π/6 typed inline (Trebuchet 14)", density: 1, width: 640,
         css: "#cap{font-family:'Trebuchet MS';font-size:14px;line-height:1.6} p{margin:0}",
         html: #"<p>For 0 ≤ <i>x</i> ≤ 2π, solve 2 sin <i>x</i> = 1, giving <i>x</i> = π/6 or <i>x</i> = 5π/6.</p>"#,
         expected: ["For 0 ≤ x ≤ 2π, solve 2 sin x = 1, giving x = π/6 or x = 5π/6."], mode: .ignoreSpaces),

    Case(id: "V09", area: .math, desc: "slide (Futura): e with a decimal exponent, ln 2 / 0.2 ≈ 3.47", width: 900,
         css: "#cap{font-family:Futura;padding:40px 56px} h1{font-size:40px;margin:0 0 24px} p{font-size:30px;margin:0 0 14px}",
         html: #"""
         <h1>Exponential growth</h1>
         <p>N(<i>t</i>) = 500e<sup>0.2<i>t</i></sup></p>
         <p>Doubling time: <i>t</i> = ln 2 / 0.2 ≈ 3.47 h</p>
         """#,
         expected: ["Exponential growth\nN(t) = 500e^(0.2t)\nDoubling time: t = ln 2 / 0.2 ≈ 3.47 h"], mode: .ignoreSpaces),

    Case(id: "V10", area: .math, desc: "cosine rule, display + rearranged as a stacked fraction", fit: true, css: stixV,
         html: #"""
         <math display="block"><msup><mi>c</mi><mn>2</mn></msup><mo>=</mo><msup><mi>a</mi><mn>2</mn></msup><mo>+</mo><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>2</mn><mi>a</mi><mi>b</mi><mi>cos</mi><mi>C</mi></math>
         <math display="block"><mi>cos</mi><mi>C</mi><mo>=</mo><mfrac><mrow><msup><mi>a</mi><mn>2</mn></msup><mo>+</mo><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><msup><mi>c</mi><mn>2</mn></msup></mrow><mrow><mn>2</mn><mi>a</mi><mi>b</mi></mrow></mfrac></math>
         """#,
         expected: vcombos("c² = a² + b² − 2ab cos C\ncos C = (a² + b² − c²)/DEN", [("DEN", ["(2ab)", "2ab"])]), mode: .ignoreSpaces),

    Case(id: "V11", area: .math, desc: "physics: Newton's gravitation F = G m₁m₂/r² (subscripts in a fraction)", fit: true, css: stixV,
         html: #"<math display="block"><mi>F</mi><mo>=</mo><mi>G</mi><mfrac><mrow><msub><mi>m</mi><mn>1</mn></msub><msub><mi>m</mi><mn>2</mn></msub></mrow><msup><mi>r</mi><mn>2</mn></msup></mfrac></math>"#,
         expected: ["F = Gm₁m₂/r²", "F = G(m₁m₂)/r²", "F = (Gm₁m₂)/r²"], mode: .ignoreSpaces),

    // MARK: Prose (6)

    Case(id: "V12", area: .prose, desc: "article (Avenir Next 17): em dashes, en-dash range, curly quotes, ellipsis", width: 680,
         css: "#cap{font-family:'Avenir Next';font-size:17px;line-height:1.6} h2{font-size:26px;margin:0 0 12px} p{margin:0 0 14px}",
         html: #"""
         <h2>The Long Road to Suffrage</h2>
         <p>Between 1918 and 1928 — a single decade — British women won the vote in two stages. The first act, summarised on pages 12–15 of the report, applied only to women over 30 who met a property test…</p>
         <p>“It was a beginning, not an end,” one campaigner wrote.</p>
         """#,
         expected: ["The Long Road to Suffrage\nBetween 1918 and 1928 — a single decade — British women won the vote in two stages. The first act, summarised on pages 12–15 of the report, applied only to women over 30 who met a property test…\n“It was a beginning, not an end,” one campaigner wrote.",
                    "The Long Road to Suffrage\nBetween 1918 and 1928 — a single decade — British women won the vote in two stages. The first act, summarised on pages 12–15 of the report, applied only to women over 30 who met a property test...\n“It was a beginning, not an end,” one campaigner wrote."]),

    Case(id: "V13", area: .prose, desc: "book page with a footnote marker and footnote under a rule (Iowan Old Style)", width: 640,
         css: "#cap{font-family:'Iowan Old Style';font-size:17px;line-height:1.6} p{margin:0 0 12px} hr{border:0;border-top:1px solid #444;width:30%;margin:10px 0 6px 0} .fn{font-size:13px}",
         html: #"""
         <p>By the late eighteenth century most European states had abandoned the doctrine of absolute rule.<sup>1</sup> Parliaments, courts and a growing press now constrained what a monarch could do.</p>
         <hr><p class="fn"><sup>1</sup> See Smith (2019), p. 42.</p>
         """#,
         expected: ["By the late eighteenth century most European states had abandoned the doctrine of absolute rule.¹ Parliaments, courts and a growing press now constrained what a monarch could do.\n¹ See Smith (2019), p. 42.",
                    "By the late eighteenth century most European states had abandoned the doctrine of absolute rule.¹ Parliaments, courts and a growing press now constrained what a monarch could do.\n1 See Smith (2019), p. 42."]),

    Case(id: "V14", area: .prose, desc: "Romanian school notice (Optima 18): lowercase ș ț ă â î, Ș capital, Târgu Mureș", width: 700,
         css: "#cap{font-family:Optima;font-size:18px;line-height:1.6} p{margin:0}",
         html: #"<p>Școala Gimnazială nr. 5 din Târgu Mureș organizează pe 15 martie un concurs de științe. Înscrierile se fac la doamna Ștefănescu, până vineri.</p>"#,
         expected: ["Școala Gimnazială nr. 5 din Târgu Mureș organizează pe 15 martie un concurs de științe. Înscrierile se fac la doamna Ștefănescu, până vineri."]),

    Case(id: "V15", area: .prose, desc: "numbers and units in prose: km, m, 12:45, −3 °C, km/h, m/s (Charter 16)", width: 720,
         css: "#cap{font-family:Charter;font-size:16px;line-height:1.6} p{margin:0}",
         html: #"<p>The 4.2 km route climbs 350 m; at 12:45 the temperature was −3 °C, with gusts of 25 km/h (about 7 m/s).</p>"#,
         expected: ["The 4.2 km route climbs 350 m; at 12:45 the temperature was −3 °C, with gusts of 25 km/h (about 7 m/s)."]),

    Case(id: "V16", area: .prose, desc: "narrow justified auto-hyphenated column (Hoefler Text 16): soft hyphens must go", width: 280,
         css: "#cap{font-family:'Hoefler Text';font-size:16px;line-height:1.45;text-align:justify;-webkit-hyphens:auto;hyphens:auto} p{margin:0}",
         html: #"<p>Photosynthesis converts electromagnetic radiation into chemical energy, which is subsequently stored in carbohydrate molecules synthesised from atmospheric carbon dioxide and water.</p>"#,
         expected: ["Photosynthesis converts electromagnetic radiation into chemical energy, which is subsequently stored in carbohydrate molecules synthesised from atmospheric carbon dioxide and water."]),

    Case(id: "V17", area: .prose, desc: "reading notes (Gill Sans): heading, bold lead-in, italic quoted paragraph", width: 660,
         css: "#cap{font-family:'Gill Sans';font-size:17px;line-height:1.55} h3{font-size:21px;margin:0 0 10px} p{margin:0 0 12px}",
         html: #"""
         <h3>Reading Notes</h3>
         <p><b>Chapter 4.</b> The narrator’s unreliability becomes obvious when she contradicts her own account of the fire.</p>
         <p><i>“I was never in the house that night,” she insists — yet two pages earlier she describes its smell.</i></p>
         """#,
         expected: ["Reading Notes\nChapter 4. The narrator’s unreliability becomes obvious when she contradicts her own account of the fire.\n“I was never in the house that night,” she insists — yet two pages earlier she describes its smell."]),

    // MARK: Lists & layout (6)

    Case(id: "V18", area: .lists, desc: "Docs outline 1. / a. / i. three levels (Avenir 16)", width: 560,
         css: "#cap{font-family:Avenir;font-size:16px;line-height:1.6} div{margin:2px 0} .l2{margin-left:30px} .l3{margin-left:60px}",
         html: #"""
         <div>1. Introduction</div>
         <div class="l2">a. Background</div>
         <div class="l2">b. Research question</div>
         <div class="l3">i. Scope</div>
         <div class="l3">ii. Limitations</div>
         <div>2. Method</div>
         <div class="l2">a. Apparatus</div>
         """#,
         expected: indentVariants("1. Introduction\n\ta. Background\n\tb. Research question\n\t\ti. Scope\n\t\tii. Limitations\n2. Method\n\ta. Apparatus")),

    Case(id: "V19", area: .lists, desc: "dark-blue slide, white Futura: title + <ol> steps, one wraps", width: 900,
         css: "#cap{background:#15315f;color:#fff;font-family:Futura;padding:40px 56px} h1{font-size:38px;margin:0 0 22px} ol{font-size:26px;line-height:1.45;margin:0;padding-left:40px} li{margin:0 0 8px}",
         html: #"""
         <h1>How to Balance an Equation</h1>
         <ol><li>Write the unbalanced equation.</li><li>Count the atoms of each element on both sides.</li><li>Add coefficients in front of formulas — never change the subscripts inside a formula to make it balance.</li><li>Check that the charges balance.</li></ol>
         """#,
         expected: ["How to Balance an Equation\n1. Write the unbalanced equation.\n2. Count the atoms of each element on both sides.\n3. Add coefficients in front of formulas — never change the subscripts inside a formula to make it balance.\n4. Check that the charges balance."]),

    Case(id: "V20", area: .layout, desc: "two-column textbook page (Charter): spanning title, paragraph across the break, figure + caption", width: 680,
         css: "#cap{font-family:Charter;font-size:14px;line-height:1.5} h2{font-size:22px;margin:0 0 12px} .cols{column-count:2;column-gap:30px} h4{font-size:15px;margin:0 0 6px} p{margin:0 0 8px} .fig{height:110px;background:#e9eef3;border:1px solid #9aa;margin:6px 0 4px} .cap{font-size:12px;font-style:italic;margin:0 0 8px}",
         html: #"""
         <h2>Chapter 7: Plate Tectonics</h2>
         <div class="cols">
         <h4>7.1 Continental drift</h4>
         <p>In 1912 Alfred Wegener proposed that the continents had once formed a single landmass, which he called Pangaea. He pointed to matching fossils and rock formations on opposite sides of the Atlantic Ocean.</p>
         <p>His idea was rejected for decades because he could not explain what force moved the continents. The discovery of sea-floor spreading in the 1960s finally supplied that mechanism and led to the modern theory of plate tectonics.</p>
         <div class="fig"></div><div class="cap">Figure 7.2 The main tectonic plates.</div>
         <h4>7.2 Plate boundaries</h4>
         <p>Plates meet at three kinds of boundary: divergent, convergent and transform.</p>
         </div>
         """#,
         expected: ["Chapter 7: Plate Tectonics\n7.1 Continental drift\nIn 1912 Alfred Wegener proposed that the continents had once formed a single landmass, which he called Pangaea. He pointed to matching fossils and rock formations on opposite sides of the Atlantic Ocean.\nHis idea was rejected for decades because he could not explain what force moved the continents. The discovery of sea-floor spreading in the 1960s finally supplied that mechanism and led to the modern theory of plate tectonics.\nFigure 7.2 The main tectonic plates.\n7.2 Plate boundaries\nPlates meet at three kinds of boundary: divergent, convergent and transform."]),

    Case(id: "V21", area: .layout, desc: "web sign-in form: labels, placeholder, checkbox + right link, button, footer", width: 420,
         css: "#cap{font-family:Seravek,Helvetica;font-size:15px;background:#fff;padding:28px;width:340px;box-sizing:content-box} h2{font-size:22px;margin:0 0 18px} label{display:block;font-weight:600;margin:0 0 6px} .in{border:1px solid #c9ccd1;border-radius:8px;height:38px;padding:0 12px;display:flex;align-items:center;margin-bottom:14px;color:#8a8f98} .row{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px} .cb{display:flex;align-items:center;gap:8px} .box{width:14px;height:14px;border:1.5px solid #888;border-radius:3px} a{color:#2563eb;text-decoration:none} .btn{background:#2563eb;color:#fff;text-align:center;border-radius:8px;padding:10px 0;font-weight:600;margin-bottom:16px} .ft{text-align:center;color:#555}",
         html: #"""
         <h2>Sign in to Classroom</h2>
         <label>Email address</label><div class="in">you@example.com</div>
         <label>Password</label><div class="in"></div>
         <div class="row"><span class="cb"><span class="box"></span>Remember me</span><a>Forgot password?</a></div>
         <div class="btn">Sign in</div>
         <div class="ft">Don’t have an account? <a>Sign up</a></div>
         """#,
         expected: tabOrSpace("Sign in to Classroom\nEmail address\nyou@example.com\nPassword\nRemember me\tForgot password?\nSign in\nDon’t have an account? Sign up")),

    Case(id: "V22", area: .layout, desc: "landing page: logo + nav row, hero title, subtitle, two buttons", width: 900,
         css: "#cap{font-family:'Avenir Next';background:#fbfaf7;padding:22px 40px 40px} .nav{display:flex;align-items:center;gap:36px;font-size:15px;margin-bottom:48px} .logo{font-weight:700;font-size:20px;margin-right:auto} h1{font-size:46px;margin:0 0 12px;text-align:center} .sub{font-size:19px;color:#555;text-align:center;margin:0 0 24px} .btns{display:flex;gap:16px;justify-content:center} .b{padding:10px 22px;border-radius:999px;border:1.5px solid #222;font-size:16px} .b.p{background:#222;color:#fff}",
         html: #"""
         <div class="nav"><span class="logo">Lumen</span><span>Home</span><span>About</span><span>Pricing</span><span>Contact</span></div>
         <h1>Build faster with less code</h1>
         <p class="sub">Lumen turns your sketches into working prototypes in minutes.</p>
         <div class="btns"><span class="b p">Get started</span><span class="b">Learn more</span></div>
         """#,
         expected: tabOrSpace("Lumen\tHome\tAbout\tPricing\tContact\nBuild faster with less code\nLumen turns your sketches into working prototypes in minutes.\nGet started\tLearn more")
                 + tabOrSpace("Lumen\nHome\tAbout\tPricing\tContact\nBuild faster with less code\nLumen turns your sketches into working prototypes in minutes.\nGet started\tLearn more")),

    Case(id: "V23", area: .layout, desc: "dark notification banner: app name + time right, sender, message", width: 420,
         css: "#cap{background:#2c2c2e;color:#f2f2f7;font-family:-apple-system,'SF Pro Text',Helvetica;font-size:14px;padding:14px 16px;border-radius:0;width:360px;box-sizing:content-box} .top{display:flex;align-items:center;gap:8px;color:#aeaeb2;font-size:12px;margin-bottom:6px} .ic{width:20px;height:20px;border-radius:5px;background:#34c759} .t{margin-left:auto} .s{font-weight:600;margin-bottom:2px}",
         html: #"""
         <div class="top"><span class="ic"></span><span>MESSAGES</span><span class="t">now</span></div>
         <div class="s">Mum</div>
         <div>Don’t forget your PE kit tomorrow!</div>
         """#,
         expected: tabOrSpace("MESSAGES\tnow\nMum\nDon’t forget your PE kit tomorrow!")),

    // MARK: Code (5)

    Case(id: "V24", area: .code, desc: "JavaScript (SF Mono 13, dark Dracula-like): async/await, template literals, ?. and ??", width: 720,
         css: "pre{margin:0;font-family:ui-monospace,'SF Mono',Menlo;font-size:13px;line-height:1.55;color:#f8f8f2} #cap{background:#282a36;padding:16px 20px} .k{color:#ff79c6} .s{color:#f1fa8c} .f{color:#50fa7b}",
         html: #"""
         <pre><span class="k">export async function</span> <span class="f">fetchGrades</span>(studentId) {
           <span class="k">const</span> res = <span class="k">await</span> fetch(<span class="s">`/api/students/${studentId}/grades`</span>);
           <span class="k">if</span> (!res.ok) {
             <span class="k">throw new</span> Error(<span class="s">`HTTP ${res.status}`</span>);
           }
           <span class="k">const</span> data = <span class="k">await</span> res.json();
           <span class="k">return</span> data.items?.filter((g) =&gt; g.score &gt;= 4) ?? [];
         }</pre>
         """#,
         expected: codeVariants(#"""
         export async function fetchGrades(studentId) {
           const res = await fetch(`/api/students/${studentId}/grades`);
           if (!res.ok) {
             throw new Error(`HTTP ${res.status}`);
           }
           const data = await res.json();
           return data.items?.filter((g) => g.score >= 4) ?? [];
         }
         """#, unit: 2), keepBlankLines: true),

    Case(id: "V25", area: .code, desc: "C, Allman braces (lone { lines), PT Mono 14, light", width: 560,
         css: "pre{margin:0;font-family:'PT Mono';font-size:14px;line-height:1.5;color:#1f2328} #cap{background:#fff;padding:16px 20px} .k{color:#8250df} .s{color:#0a3069} .p{color:#cf222e}",
         html: #"""
         <pre><span class="p">#include</span> <span class="s">&lt;stdio.h&gt;</span>

         <span class="k">int</span> main(<span class="k">int</span> argc, <span class="k">char</span> *argv[])
         {
             <span class="k">for</span> (<span class="k">int</span> i = 1; i &lt; argc; i++)
             {
                 printf(<span class="s">"%d: %s\n"</span>, i, argv[i]);
             }
             <span class="k">return</span> 0;
         }</pre>
         """#,
         expected: codeVariants(#"""
         #include <stdio.h>

         int main(int argc, char *argv[])
         {
             for (int i = 1; i < argc; i++)
             {
                 printf("%d: %s\n", i, argv[i]);
             }
             return 0;
         }
         """#), keepBlankLines: true),

    Case(id: "V26", area: .code, desc: "zsh session (SF Mono 12, black): user@host ~ % prompts, ls output, program output", width: 560,
         css: "pre{margin:0;font-family:ui-monospace,'SF Mono',Menlo;font-size:12px;line-height:1.5;color:#e6e6e6} #cap{background:#111;padding:14px 18px}",
         html: #"""
         <pre>david@MacBook ~ % cd ~/Projects/ia
         david@MacBook ia % ls -1
         analysis.py
         data.csv
         README.md
         david@MacBook ia % python3 analysis.py --n 50
         Mean: 12.48  SD: 3.07</pre>
         """#,
         expected: [#"""
         david@MacBook ~ % cd ~/Projects/ia
         david@MacBook ia % ls -1
         analysis.py
         data.csv
         README.md
         david@MacBook ia % python3 analysis.py --n 50
         Mean: 12.48  SD: 3.07
         """#, #"""
         david@MacBook ~ % cd ~/Projects/ia
         david@MacBook ia % ls -1
         analysis.py
         data.csv
         README.md
         david@MacBook ia % python3 analysis.py --n 50
         Mean: 12.48 SD: 3.07
         """#], keepBlankLines: true),

    Case(id: "V27", area: .code, desc: "JSON (Andale Mono 13, light): numbers, booleans, null, arrays", width: 520,
         css: "pre{margin:0;font-family:'Andale Mono';font-size:13px;line-height:1.5;color:#222} #cap{background:#f7f7f7;padding:14px 18px}",
         html: #"""
         <pre>{
           "id": 1042,
           "title": "Lab 3: Titration",
           "tags": ["chemistry", "HL"],
           "submitted": false,
           "grade": null,
           "scores": [6.5, 7, 5.25]
         }</pre>
         """#,
         expected: codeVariants(#"""
         {
           "id": 1042,
           "title": "Lab 3: Titration",
           "tags": ["chemistry", "HL"],
           "submitted": false,
           "grade": null,
           "scores": [6.5, 7, 5.25]
         }
         """#, unit: 2), keepBlankLines: true),

    Case(id: "V28", area: .code, desc: "1x: Python dataclass (Menlo 12): decorator, type hints, two blank lines, ** operator", density: 1, width: 700,
         css: "pre{margin:0;font-family:Menlo;font-size:12px;line-height:1.5;color:#24292f} #cap{background:#fff;padding:14px 18px} .k{color:#cf222e} .d{color:#8250df}",
         html: #"""
         <pre><span class="k">from</span> dataclasses <span class="k">import</span> dataclass


         <span class="d">@dataclass</span>
         <span class="k">class</span> Point:
             x: float
             y: float

             <span class="k">def</span> dist(self, other: "Point") -&gt; float:
                 <span class="k">return</span> ((self.x - other.x) ** 2 + (self.y - other.y) ** 2) ** 0.5</pre>
         """#,
         expected: codeVariants(#"""
         from dataclasses import dataclass


         @dataclass
         class Point:
             x: float
             y: float

             def dist(self, other: "Point") -> float:
                 return ((self.x - other.x) ** 2 + (self.y - other.y) ** 2) ** 0.5
         """#) + codeVariants(#"""
         from dataclasses import dataclass

         @dataclass
         class Point:
             x: float
             y: float

             def dist(self, other: "Point") -> float:
                 return ((self.x - other.x) ** 2 + (self.y - other.y) ** 2) ** 0.5
         """#), keepBlankLines: true),

    // MARK: Tables (5)

    Case(id: "V29", area: .tables, desc: "1x: Google-Sheets grades grid (Arial 13) with empty cells mid-row", density: 1, width: 620,
         css: "#cap{font-family:Arial;font-size:13px;padding:10px;background:#fff} table{border-collapse:collapse} td{border:1px solid #e2e2e2;padding:3px 8px;white-space:nowrap;height:18px} td.r{text-align:right} tr.h td{font-weight:bold;background:#f8f9fa}",
         html: #"""
         <table><tr class="h"><td>Student</td><td>Paper 1</td><td>Paper 2</td><td>IA</td><td>Total (%)</td></tr>
         <tr><td>Popescu A.</td><td class="r">34</td><td class="r">41</td><td class="r">18</td><td class="r">78.5</td></tr>
         <tr><td>Ionescu M.</td><td class="r">28</td><td class="r"></td><td class="r">20</td><td class="r"></td></tr>
         <tr><td>Dumitru R.</td><td class="r">40</td><td class="r">45</td><td class="r">22</td><td class="r">90.0</td></tr></table>
         """#,
         expected: ["Student\tPaper 1\tPaper 2\tIA\tTotal (%)\nPopescu A.\t34\t41\t18\t78.5\nIonescu M.\t28\t\t20\nDumitru R.\t40\t45\t22\t90.0"]),

    Case(id: "V30", area: .tables, desc: "bordered school timetable (Avenir 14): time ranges, merged Lunch row", width: 640,
         css: "#cap{font-family:Avenir;font-size:14px} table{border-collapse:collapse} td,th{border:1px solid #8a94a6;padding:6px 12px;white-space:nowrap;text-align:left} th{background:#dfe6f2} td.m{text-align:center;background:#f4f4f4;font-style:italic}",
         html: #"""
         <table><tr><th>Period</th><th>Time</th><th>Mon</th><th>Tue</th><th>Wed</th></tr>
         <tr><td>1</td><td>08:00–08:50</td><td>Maths HL</td><td>English</td><td>Physics</td></tr>
         <tr><td>2</td><td>08:55–09:45</td><td>Physics</td><td>Maths HL</td><td>TOK</td></tr>
         <tr><td>L</td><td>12:10–12:50</td><td class="m" colspan="3">Lunch</td></tr>
         <tr><td>3</td><td>12:55–13:45</td><td>Spanish</td><td>Free</td><td>Maths HL</td></tr></table>
         """#,
         expected: vcombos("Period\tTime\tMon\tTue\tWed\n1\t08:00DSH08:50\tMaths HL\tEnglish\tPhysics\n2\t08:55DSH09:45\tPhysics\tMaths HL\tTOK\nL\t12:10DSH12:50\tLunch\n3\t12:55DSH13:45\tSpanish\tFree\tMaths HL", [("DSH", ["–", "-"])])),

    Case(id: "V31", area: .tables, desc: "IB lab data table, borderless with header rule (PT Serif 15): ± uncertainties in headers", width: 680,
         css: "#cap{font-family:'PT Serif';font-size:15px} table{border-collapse:collapse} td{padding:5px 16px;white-space:nowrap;text-align:center} tr.h td{border-bottom:1.5px solid #222;border-top:1.5px solid #222;font-weight:bold}",
         html: #"""
         <table><tr class="h"><td>Length / cm ± 0.1</td><td>Time for 10 swings / s ± 0.2</td><td>Period / s</td></tr>
         <tr><td>20.0</td><td>9.0</td><td>0.90</td></tr>
         <tr><td>40.0</td><td>12.7</td><td>1.27</td></tr>
         <tr><td>60.0</td><td>15.5</td><td>1.55</td></tr>
         <tr><td>80.0</td><td>17.9</td><td>1.79</td></tr></table>
         """#,
         expected: ["Length / cm ± 0.1\tTime for 10 swings / s ± 0.2\tPeriod / s\n20.0\t9.0\t0.90\n40.0\t12.7\t1.27\n60.0\t15.5\t1.55\n80.0\t17.9\t1.79"]),

    Case(id: "V32", area: .tables, desc: "1x dark GitHub markdown table, zebra rows: versions like 18.3.1, Apache-2.0", density: 1, width: 560,
         css: "#cap{background:#0d1117;color:#e6edf3;font-family:-apple-system,Helvetica;font-size:14px;padding:16px} table{border-collapse:collapse} td,th{border:1px solid #30363d;padding:6px 13px;white-space:nowrap;text-align:left} th{font-weight:600} tr:nth-child(odd) td{background:#161b22}",
         html: #"""
         <table><tr><th>Package</th><th>Version</th><th>License</th><th>Weekly downloads</th></tr>
         <tr><td>react</td><td>18.3.1</td><td>MIT</td><td>25.1M</td></tr>
         <tr><td>lodash</td><td>4.17.21</td><td>MIT</td><td>52.4M</td></tr>
         <tr><td>typescript</td><td>5.6.2</td><td>Apache-2.0</td><td>48.0M</td></tr></table>
         """#,
         expected: ["Package\tVersion\tLicense\tWeekly downloads\nreact\t18.3.1\tMIT\t25.1M\nlodash\t4.17.21\tMIT\t52.4M\ntypescript\t5.6.2\tApache-2.0\t48.0M"]),

    Case(id: "V33", area: .tables, desc: "Wikipedia-style table with caption, Romanian city names, thousands separators, em-dash cell", width: 620,
         css: "#cap{font-family:'Helvetica Neue';font-size:14px} table{border-collapse:collapse} caption{font-weight:bold;padding:0 0 6px} td,th{border:1px solid #a2a9b1;padding:5px 10px;white-space:nowrap} th{background:#eaecf0} td.r{text-align:right}",
         html: #"""
         <table><caption>Largest cities in Romania</caption>
         <tr><th>Rank</th><th>City</th><th>County</th><th>Population (2021)</th></tr>
         <tr><td>1</td><td>Bucharest</td><td>—</td><td class="r">1,716,961</td></tr>
         <tr><td>2</td><td>Cluj-Napoca</td><td>Cluj</td><td class="r">286,598</td></tr>
         <tr><td>3</td><td>Iași</td><td>Iași</td><td class="r">271,692</td></tr>
         <tr><td>4</td><td>Constanța</td><td>Constanța</td><td class="r">263,688</td></tr>
         <tr><td>5</td><td>Timișoara</td><td>Timiș</td><td class="r">250,849</td></tr></table>
         """#,
         expected: vcombos("Largest cities in Romania\nRank\tCity\tCounty\tPopulation (2021)\n1\tBucharest\tDASH\t1,716,961\n2\tCluj-Napoca\tCluj\t286,598\n3\tIași\tIași\t271,692\n4\tConstanța\tConstanța\t263,688\n5\tTimișoara\tTimiș\t250,849", [("DASH", ["—", "-", "–"])])),

    // MARK: Robustness (4)

    Case(id: "V34", area: .robustness, desc: "Comic Sans spelling list on pale yellow", width: 520,
         css: "#cap{font-family:'Comic Sans MS';font-size:22px;background:#fff7c2;color:#333;line-height:1.5} h3{font-size:26px;margin:0 0 10px} div{margin:0}",
         html: #"""
         <h3>Spelling words for Friday</h3>
         <div>1. because</div><div>2. friend</div><div>3. beautiful</div><div>4. necessary</div>
         """#,
         expected: ["Spelling words for Friday\n1. because\n2. friend\n3. beautiful\n4. necessary"]),

    Case(id: "V35", area: .robustness, desc: "1x: 11 px grey website footer with · separators and a Romanian address", density: 1, width: 620,
         css: "#cap{font-family:Helvetica;font-size:11px;color:#767676;background:#fff;line-height:1.6} p{margin:0}",
         html: #"<p>© 2026 Lumen Labs SRL · Privacy Policy · Terms of Use · Cookie Settings</p><p>Str. Aviatorilor 12, 011853 București, România</p>"#,
         expected: ["© 2026 Lumen Labs SRL · Privacy Policy · Terms of Use · Cookie Settings\nStr. Aviatorilor 12, 011853 București, România",
                    "© 2026 Lumen Labs SRL • Privacy Policy • Terms of Use • Cookie Settings\nStr. Aviatorilor 12, 011853 București, România"]),

    Case(id: "V36", area: .robustness, desc: "white bold banner text over a noisy photo-like background", width: 760,
         css: "#cap{height:200px;background:repeating-radial-gradient(circle at 30% 40%,#c0673a 0 6px,#8e3f26 6px 11px,#d9905a 11px 15px),linear-gradient(#000,#000);display:flex;flex-direction:column;justify-content:center;align-items:center;font-family:'Avenir Next';color:#fff;text-shadow:0 2px 6px rgba(0,0,0,.7)} .a{font-size:52px;font-weight:800;letter-spacing:2px} .b{font-size:24px;font-weight:600}",
         html: #"<div class="a">SUMMER SALE</div><div class="b">Up to 50% off until 31 August</div>"#,
         expected: ["SUMMER SALE\nUp to 50% off until 31 August"]),

    Case(id: "V37", area: .robustness, desc: "chalkboard: Chalkboard SE, off-white on dark green, en-dash range and ampersand", width: 600,
         css: "#cap{font-family:'Chalkboard SE';font-size:24px;background:#2f4f3a;color:#f1f1e6;line-height:1.5} div{margin:0}",
         html: #"<div>Homework (due Thu):</div><div>p. 214, ex. 3–7 (odd)</div><div>Revise: sine &amp; cosine rules</div>"#,
         expected: vcombos("Homework (due Thu):\np. 214, ex. 3DSH7 (odd)\nRevise: sine & cosine rules", [("DSH", ["–", "-"])])),

    // MARK: No-harm (7) — plain text only; the correct output is the text itself.

    Case(id: "V38", area: .prose, desc: "no-harm: times, a date, prices (Tahoma 15)", width: 760,
         css: "#cap{font-family:Tahoma;font-size:15px;line-height:1.6} p{margin:0}",
         html: #"<p>The train leaves at 07:45 on 03/10/2026 and costs £12.50 (or $15.99 online); the return is at 18:05.</p>"#,
         expected: ["The train leaves at 07:45 on 03/10/2026 and costs £12.50 (or $15.99 online); the return is at 18:05."]),

    Case(id: "V39", area: .prose, desc: "no-harm: version numbers, a ~/ file path, an email address (Helvetica 15)", width: 780,
         css: "#cap{font-family:Helvetica;font-size:15px;line-height:1.6} p{margin:0}",
         html: #"<p>Update to v2.11.0 from ~/Downloads/BetterScreenshot-2.11.0.dmg, then write to support@example.org if macOS 14.6.1 still complains.</p>"#,
         expected: ["Update to v2.11.0 from ~/Downloads/BetterScreenshot-2.11.0.dmg, then write to support@example.org if macOS 14.6.1 still complains."]),

    Case(id: "V40", area: .prose, desc: "no-harm: x as a letter (x-axis, 2x speed-up, Exhibit X, 4 x 6) (Trebuchet 16)", width: 760,
         css: "#cap{font-family:'Trebuchet MS';font-size:16px;line-height:1.6} p{margin:0}",
         html: #"<p>Label the x-axis in seconds; the new build gives a 2x speed-up, and Exhibit X shows the 4 x 6 photo.</p>"#,
         expected: vcombos("Label the x-axis in seconds; the new build gives a 2TWO speed-up, and Exhibit X shows the 4 FOUR 6 photo.", [("TWO", ["x", "×"]), ("FOUR", ["x", "×"])])),

    Case(id: "V41", area: .prose, desc: "no-harm: plain (not superscript) ordinals, H2O/CO2 typed flat, percentages (Times 17)", width: 740,
         css: "#cap{font-family:'Times New Roman';font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>Ana came 1st, Radu 2nd and Elena 3rd; the 21st-century H2O and CO2 labels were 45% larger.</p>"#,
         expected: ["Ana came 1st, Radu 2nd and Elena 3rd; the 21st-century H2O and CO2 labels were 45% larger."]),

    Case(id: "V42", area: .prose, desc: "no-harm: arrows and bullet glyphs inside prose (Helvetica Neue 16)", width: 760,
         css: "#cap{font-family:'Helvetica Neue';font-size:16px;line-height:1.6} p{margin:0 0 8px}",
         html: #"<p>Go to File → Export → PDF, then choose A4 • Portrait • 300 dpi.</p><p>Scores rose from 12 → 15 (+25%) after the retest.</p>"#,
         expected: ["Go to File → Export → PDF, then choose A4 • Portrait • 300 dpi.\nScores rose from 12 → 15 (+25%) after the retest."]),

    Case(id: "V43", area: .prose, desc: "no-harm: hyphenated words mid-line, a.m., spaced em dash (Seravek 16)", width: 760,
         css: "#cap{font-family:Seravek;font-size:16px;line-height:1.6} p{margin:0}",
         html: #"<p>The well-known e-mail from the self-driving start-up arrived at 9:30 a.m. — please re-read it before the A-level mock.</p>"#,
         expected: ["The well-known e-mail from the self-driving start-up arrived at 9:30 a.m. — please re-read it before the A-level mock."]),

    Case(id: "V44", area: .prose, desc: "no-harm: phone number, ISBN, order id with slash (PT Sans 16)", width: 700,
         css: "#cap{font-family:'PT Sans';font-size:16px;line-height:1.6} p{margin:0}",
         html: #"<p>Call +40 721 234 567 or quote ISBN 978-0-19-852663-6 and order #A-1042/B.</p>"#,
         expected: ["Call +40 721 234 567 or quote ISBN 978-0-19-852663-6 and order #A-1042/B."]),
]
