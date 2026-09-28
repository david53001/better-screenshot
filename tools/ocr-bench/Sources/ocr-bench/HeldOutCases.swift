// Held-out cases for the 2026-09-28 re-review (docs/reviews/2026-09-28-ocr-rereview.md).
// Written by an independent reviewer AFTER the pipeline was tuned on Cases.swift, and
// deliberately not near-copies of those: different fonts (Palatino, Verdana, Baskerville,
// Source Code Pro, Monaco, Courier New, Tahoma-free SF UI), IB-style math, prose with
// look-alike traps (footnote markers, quotes, °C, ™, A0/B0, capital C/O/S/X next to a
// superscript), spreadsheets with a merged title row, terminals, UI dialogs/menus.
// Ground truth follows README.md: what a careful human would retype.

private let stix = "#cap{font-family:'STIX Two Text';font-size:30px} math[display=block]{margin:6px 0}"

/// Every combination of the accepted spellings of a repeated sub-expression.
private func combos(_ template: String, _ slot: String, _ options: [String]) -> [String] {
    var out = [template]
    while out.contains(where: { $0.contains(slot) }) {
        out = out.flatMap { s -> [String] in
            guard let r = s.range(of: slot) else { return [s] }
            return options.map { s.replacingCharacters(in: r, with: $0) }
        }
    }
    return out
}

let heldOut: [Case] = [
    // MARK: Math (13)

    Case(id: "H01", area: .math, desc: "IB geometric sequence: uₙ = u₁rⁿ⁻¹, S∞ = u₁/(1 − r)", fit: true, css: stix,
         html: #"""
         <math display="block"><msub><mi>u</mi><mi>n</mi></msub><mo>=</mo><msub><mi>u</mi><mn>1</mn></msub><msup><mi>r</mi><mrow><mi>n</mi><mo>−</mo><mn>1</mn></mrow></msup></math>
         <math display="block"><msub><mi>S</mi><mi>∞</mi></msub><mo>=</mo><mfrac><msub><mi>u</mi><mn>1</mn></msub><mrow><mn>1</mn><mo>−</mo><mi>r</mi></mrow></mfrac><mo>,</mo><mspace width="0.6em"/><mo>|</mo><mi>r</mi><mo>|</mo><mo>&lt;</mo><mn>1</mn></math>
         """#,
         expected: ["uₙ = u₁rⁿ⁻¹\nS∞ = u₁/(1 − r), |r| < 1", "uₙ = u₁rⁿ⁻¹\nS_∞ = u₁/(1 − r), |r| < 1"], mode: .ignoreSpaces),

    Case(id: "H02", area: .math, desc: "log laws in a sentence (Palatino, HTML sub/sup)", width: 820,
         css: "#cap{font-family:Palatino;font-size:18px;line-height:1.7} p{margin:0}",
         html: #"<p>Using log<sub>a</sub>(xy) = log<sub>a</sub>x + log<sub>a</sub>y, we find that log<sub>2</sub>32 = 5 and ln e<sup>3</sup> = 3.</p>"#,
         expected: ["Using logₐ(xy) = logₐx + logₐy, we find that log₂32 = 5 and ln e³ = 3."], mode: .ignoreSpaces),

    Case(id: "H03", area: .math, desc: "trig in HTML (Times italic θ, CSS stacked fraction)", fit: true,
         css: "#cap{font-family:'Times New Roman';font-size:28px;line-height:2.3} .fr{display:inline-flex;flex-direction:column;vertical-align:middle;text-align:center;line-height:1.15;margin:0 4px} .fr>span:first-child{border-bottom:1.5px solid #111;padding:0 4px}",
         html: #"""
         <div>tan <i>θ</i> = <span class="fr"><span>sin <i>θ</i></span><span>cos <i>θ</i></span></span></div>
         <div>cos 2<i>θ</i> = 1 − 2 sin<sup>2</sup> <i>θ</i></div>
         """#,
         expected: ["tan θ = (sin θ)/(cos θ)\ncos 2θ = 1 − 2sin²θ", "tan θ = sin θ/cos θ\ncos 2θ = 1 − 2sin²θ"], mode: .ignoreSpaces),

    Case(id: "H04", area: .math, desc: "indefinite integral with a fraction on the right", fit: true, css: stix,
         html: #"<math display="block"><mo>∫</mo><msup><mi>x</mi><mn>3</mn></msup><mspace width="0.2em"/><mi>d</mi><mi>x</mi><mo>=</mo><mfrac><msup><mi>x</mi><mn>4</mn></msup><mn>4</mn></mfrac><mo>+</mo><mi>C</mi></math>"#,
         expected: ["∫ x³ dx = x⁴/4 + C"], mode: .ignoreSpaces),

    Case(id: "H05", area: .math, desc: "conditional probability P(A|B) + complement P(A′)", fit: true, css: stix,
         html: #"""
         <math display="block"><mi>P</mi><mo stretchy="false">(</mo><mi>A</mi><mo stretchy="false">|</mo><mi>B</mi><mo stretchy="false">)</mo><mo>=</mo><mfrac><mrow><mi>P</mi><mo stretchy="false">(</mo><mi>A</mi><mo>∩</mo><mi>B</mi><mo stretchy="false">)</mo></mrow><mrow><mi>P</mi><mo stretchy="false">(</mo><mi>B</mi><mo stretchy="false">)</mo></mrow></mfrac></math>
         <math display="block"><mi>P</mi><mo stretchy="false">(</mo><msup><mi>A</mi><mo>′</mo></msup><mo stretchy="false">)</mo><mo>=</mo><mn>1</mn><mo>−</mo><mi>P</mi><mo stretchy="false">(</mo><mi>A</mi><mo stretchy="false">)</mo></math>
         """#,
         expected: ["P(A|B) = P(A ∩ B)/P(B)\nP(A′) = 1 − P(A)"], mode: .ignoreSpaces),

    Case(id: "H06", area: .math, desc: "vector magnitude: root over sub+sup scripts", fit: true, css: stix,
         html: #"<math display="block"><mo stretchy="false">|</mo><mi mathvariant="bold">v</mi><mo stretchy="false">|</mo><mo>=</mo><msqrt><msubsup><mi>v</mi><mn>1</mn><mn>2</mn></msubsup><mo>+</mo><msubsup><mi>v</mi><mn>2</mn><mn>2</mn></msubsup><mo>+</mo><msubsup><mi>v</mi><mn>3</mn><mn>2</mn></msubsup></msqrt></math>"#,
         expected: ["|v| = √(v₁² + v₂² + v₃²)"], mode: .ignoreSpaces),

    Case(id: "H07", area: .math, desc: "1x: physics sentence, Verdana 14 (m s⁻², Eₖ = ½mv², × 10⁵)", density: 1, width: 640,
         css: "#cap{font-family:Verdana;font-size:14px;line-height:1.6} p{margin:0}",
         html: #"<p>The trolley accelerates at 2.5 m s<sup>−2</sup>, so its kinetic energy E<sub>k</sub> = ½mv<sup>2</sup> reaches 4.5 × 10<sup>5</sup> J.</p>"#,
         expected: combos("The trolley accelerates at 2.5 m s⁻², so its kinetic energy Eₖ = HALFmv² reaches 4.5 × 10⁵ J.",
                          "HALF", ["½", "(1/2)", "1/2", "1/2 "])),

    Case(id: "H08", area: .math, desc: "chemistry: ionic charges Ba²⁺, SO₄²⁻, OH⁻ (Georgia)", width: 560,
         css: "#cap{font-family:Georgia;font-size:22px;line-height:1.9} p{margin:0}",
         html: #"<p>Ba<sup>2+</sup> + SO<sub>4</sub><sup>2−</sup> → BaSO<sub>4</sub></p><p>Fe<sup>3+</sup> + 3OH<sup>−</sup> → Fe(OH)<sub>3</sub></p>"#,
         expected: ["Ba²⁺ + SO₄²⁻ → BaSO₄\nFe³⁺ + 3OH⁻ → Fe(OH)₃"], mode: .ignoreSpaces),

    Case(id: "H09", area: .math, desc: "nested exponent: y = e^(−x²), f′(x) = −2xe^(−x²)", fit: true, css: stix,
         html: #"""
         <math display="block"><mi>y</mi><mo>=</mo><msup><mi>e</mi><mrow><mo>−</mo><msup><mi>x</mi><mn>2</mn></msup></mrow></msup></math>
         <math display="block"><msup><mi>f</mi><mo>′</mo></msup><mo stretchy="false">(</mo><mi>x</mi><mo stretchy="false">)</mo><mo>=</mo><mo>−</mo><mn>2</mn><mi>x</mi><msup><mi>e</mi><mrow><mo>−</mo><msup><mi>x</mi><mn>2</mn></msup></mrow></msup></math>
         """#,
         expected: combos("y = eEXP\nf′(x) = −2xeEXP", "EXP", ["^(−x²)", "⁻ˣ²"]), mode: .ignoreSpaces),

    Case(id: "H10", area: .math, desc: "inline stacked fractions inside a sentence (Times 19)", width: 760,
         css: "#cap{font-family:'Times New Roman';font-size:19px;line-height:2.2} p{margin:0}",
         html: #"<p>If the probability of rain is <math><mfrac><mn>3</mn><mn>10</mn></mfrac></math>, then the probability of no rain is <math><mn>1</mn><mo>−</mo><mfrac><mn>3</mn><mn>10</mn></mfrac><mo>=</mo><mfrac><mn>7</mn><mn>10</mn></mfrac></math>.</p>"#,
         expected: ["If the probability of rain is 3/10, then the probability of no rain is 1 − 3/10 = 7/10."], mode: .ignoreSpaces),

    Case(id: "H11", area: .math, desc: "derivative from first principles (lim over fraction)", fit: true, css: stix,
         html: #"<math display="block"><msup><mi>f</mi><mo>′</mo></msup><mo stretchy="false">(</mo><mi>x</mi><mo stretchy="false">)</mo><mo>=</mo><munder><mi>lim</mi><mrow><mi>h</mi><mo>→</mo><mn>0</mn></mrow></munder><mfrac><mrow><mi>f</mi><mo stretchy="false">(</mo><mi>x</mi><mo>+</mo><mi>h</mi><mo stretchy="false">)</mo><mo>−</mo><mi>f</mi><mo stretchy="false">(</mo><mi>x</mi><mo stretchy="false">)</mo></mrow><mi>h</mi></mfrac></math>"#,
         expected: ["f′(x) = lim_(h→0) (f(x + h) − f(x))/h", "f′(x) = lim(h→0) (f(x + h) − f(x))/h", "f′(x) = lim h→0 (f(x + h) − f(x))/h"],
         mode: .ignoreSpaces),

    Case(id: "H12", area: .math, desc: "discriminant sentence (Helvetica 16, HTML sup, Δ)", width: 780,
         css: "#cap{font-family:Helvetica;font-size:16px;line-height:1.6} p{margin:0}",
         html: #"<p>The equation ax<sup>2</sup> + bx + c = 0 has two distinct real roots when Δ = b<sup>2</sup> − 4ac &gt; 0.</p>"#,
         expected: ["The equation ax² + bx + c = 0 has two distinct real roots when Δ = b² − 4ac > 0."]),

    Case(id: "H13", area: .math, desc: "IB exam question: cubic in the stem, f′(x), marks at right", width: 720,
         css: "#cap{font-family:'Times New Roman';font-size:17px;line-height:1.5} .row{display:flex;align-items:flex-end;margin:6px 0} .row .t{flex:1;padding-right:40px} .stem{margin-bottom:10px}",
         html: #"""
         <div class="stem">4. Let <i>f</i>(<i>x</i>) = 2<i>x</i><sup>3</sup> − 3<i>x</i><sup>2</sup> − 12<i>x</i> + 5.</div>
         <div class="row"><div class="t">(a) Find <i>f</i>′(<i>x</i>).</div><div>[2]</div></div>
         <div class="row"><div class="t">(b) Hence find the coordinates of the local minimum of the graph of <i>f</i>.</div><div>[4]</div></div>
         """#,
         expected: tabOrSpace("4. Let f(x) = 2x³ − 3x² − 12x + 5.\n(a) Find f′(x).\t[2]\n(b) Hence find the coordinates of the local minimum of the graph of f.\t[4]")),

    // MARK: Prose with look-alike traps (5)

    Case(id: "H14", area: .prose, desc: "footnote markers + curly quotes + apostrophes (Georgia)", width: 660,
         css: "#cap{font-family:Georgia;font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>The Peace of Westphalia<sup>1</sup> was signed in 1648. Historians often call it “the birth of the modern state,”<sup>2</sup> although the Emperor’s authority wasn’t fully broken until much later.</p>"#,
         expected: ["The Peace of Westphalia¹ was signed in 1648. Historians often call it “the birth of the modern state,”² although the Emperor’s authority wasn’t fully broken until much later.",
                    "The Peace of Westphalia was signed in 1648. Historians often call it “the birth of the modern state,” although the Emperor’s authority wasn’t fully broken until much later."]),

    Case(id: "H15", area: .prose, desc: "symbols: 1st/2nd, 25 °C, café, 3×, ™, €1,299, 20%, Room B0.12", width: 720,
         css: "#cap{font-family:Helvetica;font-size:16px;line-height:1.6} p{margin:0 0 10px}",
         html: #"""
         <p>On the 1st and 2nd of May it reached 25 °C in Bucharest, so the café sold 3× more iced tea.</p>
         <p>The new ThinkPad™ costs €1,299 (about 20% more), and Room B0.12 is on the ground floor.</p>
         """#,
         expected: ["On the 1st and 2nd of May it reached 25 °C in Bucharest, so the café sold 3× more iced tea.\nThe new ThinkPad™ costs €1,299 (about 20% more), and Room B0.12 is on the ground floor."]),

    Case(id: "H16", area: .prose, desc: "capitals C/OXO/SOS/X and A0 in lines that also hold m² / CO₂ (Verdana)", width: 780,
         css: "#cap{font-family:Verdana;font-size:16px;line-height:1.7} p{margin:0 0 10px}",
         html: #"""
         <p>In Section C, each OXO cube adds 2 g of salt; a 5 m<sup>2</sup> SOS banner needs 0.5 L of paint.</p>
         <p>Print it on A0 paper so the CO<sub>2</sub> graph and Table X are readable from 10 m away.</p>
         """#,
         expected: ["In Section C, each OXO cube adds 2 g of salt; a 5 m² SOS banner needs 0.5 L of paint.\nPrint it on A0 paper so the CO₂ graph and Table X are readable from 10 m away."]),

    Case(id: "H17", area: .prose, desc: "dialogue: curly quotes, contractions, ’90s, rock ’n’ roll (Baskerville)", width: 640,
         css: "#cap{font-family:Baskerville;font-size:19px;line-height:1.55} p{margin:0 0 10px}",
         html: #"""
         <p>“It’s not Maria’s fault,” said Ioana. “We’ll finish the lab report by 5 o’clock — I promise.”</p>
         <p>The ’90s rock ’n’ roll revival didn’t last, but the students’ enthusiasm did.</p>
         """#,
         expected: ["“It’s not Maria’s fault,” said Ioana. “We’ll finish the lab report by 5 o’clock — I promise.”\nThe ’90s rock ’n’ roll revival didn’t last, but the students’ enthusiasm did."]),

    Case(id: "H18", area: .prose, desc: "Word-style superscript ordinals 19th / 2nd / 3rd (Times)", width: 700,
         css: "#cap{font-family:'Times New Roman';font-size:18px;line-height:1.6} p{margin:0}",
         html: #"<p>The 19<sup>th</sup> century saw rapid industrialisation. The 2<sup>nd</sup> edition of the book was published on the 3<sup>rd</sup> of March.</p>"#,
         expected: ["The 19th century saw rapid industrialisation. The 2nd edition of the book was published on the 3rd of March.",
                    "The 19ᵗʰ century saw rapid industrialisation. The 2ⁿᵈ edition of the book was published on the 3ʳᵈ of March."]),

    // MARK: Lists (1)

    Case(id: "H19", area: .lists, desc: "IB question parts: 1. / (a) / (i) (ii) nesting (Arial)", width: 620,
         css: "#cap{font-family:Arial;font-size:16px;line-height:1.6} div{margin:3px 0} .l2{margin-left:28px} .l3{margin-left:56px}",
         html: #"""
         <div>1. The table shows the heights of 30 plants.</div>
         <div class="l2">(a) Calculate the mean height.</div>
         <div class="l3">(i) Show that the median is 42 cm.</div>
         <div class="l3">(ii) Hence find the interquartile range.</div>
         <div class="l2">(b) Draw a box-and-whisker diagram.</div>
         <div>2. A second sample of 20 plants was measured.</div>
         """#,
         expected: indentVariants("1. The table shows the heights of 30 plants.\n\t(a) Calculate the mean height.\n\t\t(i) Show that the median is 42 cm.\n\t\t(ii) Hence find the interquartile range.\n\t(b) Draw a box-and-whisker diagram.\n2. A second sample of 20 plants was measured.")),

    // MARK: Code (4)

    Case(id: "H20", area: .code, desc: "SQL, Source Code Pro 14, caps keywords, <>, 'O''Brien'", width: 660,
         css: "pre{margin:0;font-family:'Source Code Pro';font-size:14px;line-height:1.55;color:#24292f} #cap{background:#fff;padding:16px 20px} .k{color:#0000c0;font-weight:600} .s{color:#a31515}",
         html: #"""
         <pre><span class="k">SELECT</span> s.name, <span class="k">COUNT</span>(*) <span class="k">AS</span> n_courses
         <span class="k">FROM</span> students s
         <span class="k">JOIN</span> enrolments e <span class="k">ON</span> e.student_id = s.id
         <span class="k">WHERE</span> s.year &gt;= 11 <span class="k">AND</span> s.name &lt;&gt; <span class="s">'O''Brien'</span>
         <span class="k">GROUP BY</span> s.name
         <span class="k">HAVING</span> <span class="k">COUNT</span>(*) &gt; 2
         <span class="k">ORDER BY</span> n_courses <span class="k">DESC</span>;</pre>
         """#,
         expected: [#"""
         SELECT s.name, COUNT(*) AS n_courses
         FROM students s
         JOIN enrolments e ON e.student_id = s.id
         WHERE s.year >= 11 AND s.name <> 'O''Brien'
         GROUP BY s.name
         HAVING COUNT(*) > 2
         ORDER BY n_courses DESC;
         """#], keepBlankLines: true),

    Case(id: "H21", area: .code, desc: "terminal (Monaco 12, dark): custom prompt, git log, output", width: 560,
         css: "pre{margin:0;font-family:Monaco;font-size:12px;line-height:1.5;color:#e0e0e0} #cap{background:#1b1b1b;padding:14px 18px} .p{color:#7ec16e}",
         html: #"""
         <pre><span class="p">~/ib-ia $</span> git log --oneline -3
         a1b2c3d Fix off-by-one in parser
         9f8e7d6 Add CSV export (#42)
         0c1d2e3 Initial commit
         <span class="p">~/ib-ia $</span> python3 -c "print(2**10)"
         1024</pre>
         """#,
         expected: [#"""
         ~/ib-ia $ git log --oneline -3
         a1b2c3d Fix off-by-one in parser
         9f8e7d6 Add CSV export (#42)
         0c1d2e3 Initial commit
         ~/ib-ia $ python3 -c "print(2**10)"
         1024
         """#], keepBlankLines: true),

    Case(id: "H22", area: .code, desc: "Python in a VS Code gutter starting at line 12 (Menlo, dark)", width: 640,
         css: "#cap{background:#1e1e1e;padding:12px 8px;font-family:Menlo;font-size:13px;color:#d4d4d4} table{border-collapse:collapse} td{padding:0 12px;line-height:1.6;white-space:pre} td.ln{color:#858585;text-align:right} .k{color:#569cd6} .s{color:#ce9178} .c{color:#6a9955} .f{color:#dcdcaa} .n{color:#b5cea8}",
         html: #"""
         <table>
         <tr><td class="ln">12</td><td><span class="k">def</span> <span class="f">mean</span>(values):</td></tr>
         <tr><td class="ln">13</td><td>    <span class="s">"""Return the arithmetic mean."""</span></td></tr>
         <tr><td class="ln">14</td><td>    <span class="k">if not</span> values:</td></tr>
         <tr><td class="ln">15</td><td>        <span class="k">raise</span> ValueError(<span class="s">"empty list"</span>)</td></tr>
         <tr><td class="ln">16</td><td>    total = sum(v <span class="k">for</span> v <span class="k">in</span> values <span class="k">if</span> v <span class="k">is not</span> None)</td></tr>
         <tr><td class="ln">17</td><td>    <span class="k">return</span> total / len(values)</td></tr>
         <tr><td class="ln">18</td><td> </td></tr>
         <tr><td class="ln">19</td><td>print(<span class="s">f"{mean([<span class="n">3</span>, <span class="n">4</span>, <span class="n">5</span>]):.2f}"</span>)  <span class="c"># 4.00</span></td></tr>
         </table>
         """#,
         expected: codeVariants(#"""
         def mean(values):
             """Return the arithmetic mean."""
             if not values:
                 raise ValueError("empty list")
             total = sum(v for v in values if v is not None)
             return total / len(values)

         print(f"{mean([3, 4, 5]):.2f}")  # 4.00
         """#) + codeVariants(#"""
         def mean(values):
             """Return the arithmetic mean."""
             if not values:
                 raise ValueError("empty list")
             total = sum(v for v in values if v is not None)
             return total / len(values)

         print(f"{mean([3, 4, 5]):.2f}") # 4.00
         """#), keepBlankLines: true),

    Case(id: "H23", area: .code, desc: "1x: JSON (package.json) in Courier New 13", density: 1, width: 520,
         css: "pre{margin:0;font-family:'Courier New';font-size:13px;line-height:1.45;color:#222} #cap{background:#fafafa;padding:14px 18px}",
         html: #"""
         <pre>{
           "name": "ocr-bench",
           "version": "1.0.2",
           "private": true,
           "scripts": {
             "test": "node --test",
             "lint": "eslint src/"
           },
           "files": ["dist", "README.md"],
           "timeout": 0.75
         }</pre>
         """#,
         expected: codeVariants(#"""
         {
           "name": "ocr-bench",
           "version": "1.0.2",
           "private": true,
           "scripts": {
             "test": "node --test",
             "lint": "eslint src/"
           },
           "files": ["dist", "README.md"],
           "timeout": 0.75
         }
         """#, unit: 2), keepBlankLines: true),

    // MARK: Tables (4)

    Case(id: "H24", area: .tables, desc: "spreadsheet: merged title row, thousands separators, %", width: 560,
         css: "#cap{font-family:Arial;font-size:13px;padding:10px} table{border-collapse:collapse} td{border:1px solid #d0d0d0;padding:4px 10px} td.r{text-align:right} .t{font-weight:bold;text-align:center;background:#e8eef7} tr.h td{font-weight:bold;background:#f3f3f3}",
         html: #"""
         <table><tr><td class="t" colspan="4">Q3 Sales by Region</td></tr>
         <tr class="h"><td>Region</td><td>Units</td><td>Revenue (€)</td><td>Change</td></tr>
         <tr><td>North</td><td class="r">1,204</td><td class="r">36,120.00</td><td class="r">+4.5%</td></tr>
         <tr><td>South</td><td class="r">986</td><td class="r">29,580.50</td><td class="r">−2.1%</td></tr>
         <tr><td>East</td><td class="r">2,310</td><td class="r">69,300.00</td><td class="r">+12.0%</td></tr>
         <tr><td>West</td><td class="r">745</td><td class="r">22,350.25</td><td class="r">0.0%</td></tr></table>
         """#,
         expected: ["Q3 Sales by Region\nRegion\tUnits\tRevenue (€)\tChange\nNorth\t1,204\t36,120.00\t+4.5%\nSouth\t986\t29,580.50\t−2.1%\nEast\t2,310\t69,300.00\t+12.0%\nWest\t745\t22,350.25\t0.0%"]),

    Case(id: "H25", area: .tables, desc: "borderless financial statement, (negatives), bold subtotals (Georgia)", width: 560,
         css: "#cap{font-family:Georgia;font-size:15px} table{border-collapse:collapse} td{padding:5px 14px} td.r{text-align:right} tr.h td{border-bottom:1.5px solid #333;font-style:italic} tr.b td{font-weight:bold;border-top:1px solid #333}",
         html: #"""
         <table><tr class="h"><td>(in € thousands)</td><td class="r">2024</td><td class="r">2023</td></tr>
         <tr><td>Revenue</td><td class="r">12,450</td><td class="r">11,020</td></tr>
         <tr><td>Cost of sales</td><td class="r">(7,310)</td><td class="r">(6,880)</td></tr>
         <tr class="b"><td>Gross profit</td><td class="r">5,140</td><td class="r">4,140</td></tr>
         <tr><td>Operating expenses</td><td class="r">(3,905)</td><td class="r">(3,760)</td></tr>
         <tr class="b"><td>Net income</td><td class="r">1,235</td><td class="r">380</td></tr></table>
         """#,
         expected: ["(in € thousands)\t2024\t2023\nRevenue\t12,450\t11,020\nCost of sales\t(7,310)\t(6,880)\nGross profit\t5,140\t4,140\nOperating expenses\t(3,905)\t(3,760)\nNet income\t1,235\t380"]),

    Case(id: "H26", area: .tables, desc: "dark-mode Notion-style table with an empty cell", width: 600,
         css: "#cap{background:#191919;color:#e3e3e3;font-family:Helvetica;font-size:14px;padding:16px} table{border-collapse:collapse} td{border:1px solid #373737;padding:7px 12px} tr:first-child td{color:#9b9b9b}",
         html: #"""
         <table><tr><td>Task</td><td>Status</td><td>Due</td><td>Owner</td></tr>
         <tr><td>Read chapter 5</td><td>Done</td><td>Oct 3</td><td>Ana</td></tr>
         <tr><td>Draft lab report</td><td>In progress</td><td>Oct 10</td><td></td></tr>
         <tr><td>Book the gym</td><td>Not started</td><td>Oct 14</td><td>Mihai</td></tr></table>
         """#,
         expected: ["Task\tStatus\tDue\tOwner\nRead chapter 5\tDone\tOct 3\tAna\nDraft lab report\tIn progress\tOct 10\nBook the gym\tNot started\tOct 14\tMihai"]),

    Case(id: "H27", area: .tables, desc: "physics units table: Greek ρ, kg m⁻³, m s⁻¹ in cells (Times)", width: 520,
         css: "#cap{font-family:'Times New Roman';font-size:17px} table{border-collapse:collapse} td,th{border:1px solid #999;padding:6px 14px;text-align:left} th{background:#eee}",
         html: #"""
         <table><tr><th>Quantity</th><th>Symbol</th><th>SI unit</th></tr>
         <tr><td>Density</td><td><i>ρ</i></td><td>kg m<sup>−3</sup></td></tr>
         <tr><td>Speed</td><td><i>v</i></td><td>m s<sup>−1</sup></td></tr>
         <tr><td>Momentum</td><td><i>p</i></td><td>kg m s<sup>−1</sup></td></tr>
         <tr><td>Charge</td><td><i>Q</i></td><td>C</td></tr></table>
         """#,
         expected: ["Quantity\tSymbol\tSI unit\nDensity\tρ\tkg m⁻³\nSpeed\tv\tm s⁻¹\nMomentum\tp\tkg m s⁻¹\nCharge\tQ\tC"]),

    // MARK: Layout & UI (5)

    Case(id: "H28", area: .layout, desc: "macOS alert: icon, bold title, wrapped centred message, checkbox, buttons", width: 400,
         css: "#cap{font-family:-apple-system,'SF Pro Text',Helvetica;font-size:13px;background:#f0f0f0;padding:20px;width:300px;box-sizing:content-box} .icon{width:56px;height:56px;border-radius:12px;background:linear-gradient(#6fa8ff,#2f6fe0);margin:0 auto 12px} .t{font-weight:700;text-align:center;font-size:14px;margin-bottom:6px} .m{text-align:center;color:#333;margin-bottom:14px;line-height:1.35} .cb{display:flex;align-items:center;gap:6px;margin-bottom:14px} .box{width:13px;height:13px;border:1px solid #999;border-radius:3px;background:#fff} .btns{display:flex;gap:8px} .b{flex:1;text-align:center;padding:5px 0;border-radius:6px;background:#fff;border:1px solid #c8c8c8} .b.d{background:#e5483f;color:#fff;border-color:#e5483f}",
         html: #"""
         <div class="icon"></div>
         <div class="t">Delete “Lab Report.docx”?</div>
         <div class="m">This item will be deleted immediately. You can’t undo this action.</div>
         <div class="cb"><span class="box"></span>Don’t ask again</div>
         <div class="btns"><div class="b">Cancel</div><div class="b d">Delete</div></div>
         """#,
         expected: tabOrSpace("Delete “Lab Report.docx”?\nThis item will be deleted immediately. You can’t undo this action.\nDon’t ask again\nCancel\tDelete")),

    Case(id: "H29", area: .layout, desc: "context menu with right-aligned ⌘ shortcuts and separators", width: 300,
         css: "#cap{font-family:-apple-system,'SF Pro Text',Helvetica;font-size:14px;background:#ececec;padding:6px;width:230px;box-sizing:content-box} .i{display:flex;justify-content:space-between;padding:4px 12px} .k{color:#777} .sep{height:1px;background:#ccc;margin:5px 10px} .dis{color:#aaa}",
         html: #"""
         <div class="i"><span>Undo Typing</span><span class="k">⌘Z</span></div>
         <div class="sep"></div>
         <div class="i"><span>Cut</span><span class="k">⌘X</span></div>
         <div class="i"><span>Copy</span><span class="k">⌘C</span></div>
         <div class="i"><span>Paste</span><span class="k">⌘V</span></div>
         <div class="i dis"><span>Paste and Match Style</span><span class="k">⌥⇧⌘V</span></div>
         <div class="sep"></div>
         <div class="i"><span>Select All</span><span class="k">⌘A</span></div>
         """#,
         expected: tabOrSpace("Undo Typing\t⌘Z\nCut\t⌘X\nCopy\t⌘C\nPaste\t⌘V\nPaste and Match Style\t⌥⇧⌘V\nSelect All\t⌘A")),

    Case(id: "H30", area: .layout, desc: "settings window: sidebar + label/value rows", width: 640,
         css: "#cap{display:flex;font-family:-apple-system,'SF Pro Text',Helvetica;font-size:13px;background:#fff;padding:0} .side{width:170px;background:#f2f2f4;padding:14px 10px} .side div{padding:5px 8px;border-radius:6px} .side .sel{background:#0a64d8;color:#fff} .main{flex:1;padding:18px 22px} h2{font-size:18px;margin:0 0 14px} .row{display:flex;justify-content:space-between;padding:9px 12px;border-bottom:1px solid #e5e5e5} .v{color:#555}",
         html: #"""
         <div class="side"><div>General</div><div class="sel">Appearance</div><div>Wi-Fi</div><div>Bluetooth</div><div>Displays</div></div>
         <div class="main"><h2>Appearance</h2>
         <div class="row"><span>Appearance</span><span class="v">Auto</span></div>
         <div class="row"><span>Accent colour</span><span class="v">Multicolour</span></div>
         <div class="row"><span>Show scroll bars</span><span class="v">When scrolling</span></div>
         <div class="row"><span>Click in the scroll bar to</span><span class="v">Jump to the next page</span></div></div>
         """#,
         expected: {
             let side = "General\nAppearance\nWi-Fi\nBluetooth\nDisplays"
             let pane = "Appearance\nAppearance\tAuto\nAccent colour\tMulticolour\nShow scroll bars\tWhen scrolling\nClick in the scroll bar to\tJump to the next page"
             return tabOrSpace(side + "\n" + pane) + tabOrSpace(pane + "\n" + side)
         }()),

    Case(id: "H31", area: .layout, desc: "two-column lab report: headings, figure + caption, paragraph across the column break", width: 640,
         css: "#cap{font-family:'Times New Roman';font-size:14px;line-height:1.45} .cols{column-count:2;column-gap:28px;text-align:justify} h3{font-size:15px;margin:0 0 6px} p{margin:0 0 8px} .fig{height:120px;background:#f1f1f1;border:1px solid #bbb;margin:6px 0 4px} .cap{font-size:12px;text-align:center;margin:0 0 10px}",
         html: #"""
         <div class="cols">
         <h3>1. Introduction</h3>
         <p>Enzymes are biological catalysts that speed up chemical reactions without being used up. Their activity depends strongly on temperature and pH.</p>
         <div class="fig"></div><div class="cap">Figure 1. Apparatus used to measure the rate of reaction.</div>
         <p>In this investigation the effect of temperature on the activity of the enzyme catalase was measured by collecting the oxygen produced when hydrogen peroxide is broken down at five different temperatures.</p>
         <h3>2. Method</h3>
         <p>A water bath was used to keep each test tube at a constant temperature for ten minutes before the enzyme was added.</p>
         </div>
         """#,
         expected: ["1. Introduction\nEnzymes are biological catalysts that speed up chemical reactions without being used up. Their activity depends strongly on temperature and pH.\nFigure 1. Apparatus used to measure the rate of reaction.\nIn this investigation the effect of temperature on the activity of the enzyme catalase was measured by collecting the oxygen produced when hydrogen peroxide is broken down at five different temperatures.\n2. Method\nA water bath was used to keep each test tube at a constant temperature for ten minutes before the enzyme was added."]),

    Case(id: "H32", area: .layout, desc: "slide: title, centred formula F = ma, bullets with m s⁻²", width: 960,
         css: "#cap{font-family:'Helvetica Neue';padding:40px 56px;background:#fff} h1{font-size:40px;margin:0 0 24px} .f{font-size:48px;text-align:center;margin:10px 0 24px;font-family:'STIX Two Text'} ul{font-size:26px;line-height:1.5;margin:0;padding-left:34px}",
         html: #"""
         <h1>Newton’s Second Law</h1>
         <div class="f"><i>F</i> = <i>ma</i></div>
         <ul><li>where <i>F</i> is the net force in newtons (N)</li><li><i>m</i> is the mass in kilograms (kg)</li><li><i>a</i> is the acceleration in m s<sup>−2</sup></li></ul>
         """#,
         expected: ["Newton’s Second Law\nF = ma\n• where F is the net force in newtons (N)\n• m is the mass in kilograms (kg)\n• a is the acceleration in m s⁻²"]),

    // MARK: Robustness (3)

    Case(id: "H33", area: .robustness, desc: "1x: Romanian, Verdana 12, capital Ș Ț, „…” quotes", density: 1, width: 560,
         css: "#cap{font-family:Verdana;font-size:12px;line-height:1.5} p{margin:0 0 6px}",
         html: #"<p>„Ștefan cel Mare” a domnit în Moldova între 1457 și 1504.</p><p>Țara Românească și Transilvania au fost unite în 1600 de Mihai Viteazul, însă unirea n-a durat.</p>"#,
         expected: ["„Ștefan cel Mare” a domnit în Moldova între 1457 și 1504.\nȚara Românească și Transilvania au fost unite în 1600 de Mihai Viteazul, însă unirea n-a durat.",
                    "\"Ștefan cel Mare\" a domnit în Moldova între 1457 și 1504.\nȚara Românească și Transilvania au fost unite în 1600 de Mihai Viteazul, însă unirea n-a durat."]),

    Case(id: "H34", area: .robustness, desc: "video frame: outlined white subtitle on a dark gradient", width: 760,
         css: "#cap{height:220px;background:linear-gradient(160deg,#2b3a42 0%,#51606b 45%,#1a1f24 100%);display:flex;flex-direction:column;justify-content:flex-end;align-items:center;padding:24px;font-family:Helvetica;font-size:26px;color:#fff;text-shadow:-2px -2px 0 #000,2px -2px 0 #000,-2px 2px 0 #000,2px 2px 0 #000;text-align:center;line-height:1.3}",
         html: #"<div>I never said she stole my money —</div><div>someone else did.</div>"#,
         expected: ["I never said she stole my money — someone else did.", "I never said she stole my money —\nsomeone else did."]),

    Case(id: "H35", area: .robustness, desc: "icon-only toolbar (no text at all)", width: 420,
         css: "#cap{background:#f5f5f7;padding:14px;display:flex;gap:18px;align-items:center} svg{display:block}",
         html: #"""
         <svg width="28" height="28"><circle cx="14" cy="14" r="10" fill="none" stroke="#444" stroke-width="2"/></svg>
         <svg width="28" height="28"><path d="M14 4 L25 24 L3 24 Z" fill="none" stroke="#444" stroke-width="2"/></svg>
         <svg width="28" height="28"><rect x="4" y="4" width="20" height="20" rx="5" fill="none" stroke="#444" stroke-width="2"/></svg>
         <svg width="28" height="28"><circle cx="12" cy="12" r="7" fill="none" stroke="#444" stroke-width="2"/><line x1="17" y1="17" x2="25" y2="25" stroke="#444" stroke-width="2.5"/></svg>
         <svg width="28" height="28"><path d="M14 24 C4 16 3 9 8 6 C11 4 13 6 14 8 C15 6 17 4 20 6 C25 9 24 16 14 24 Z" fill="#e0524f"/></svg>
         <svg width="28" height="28"><rect x="5" y="7" width="18" height="2.5" fill="#444"/><rect x="5" y="13" width="18" height="2.5" fill="#444"/><rect x="5" y="19" width="18" height="2.5" fill="#444"/></svg>
         <svg width="28" height="28"><circle cx="14" cy="14" r="5" fill="none" stroke="#444" stroke-width="2"/><g stroke="#444" stroke-width="3"><line x1="14" y1="2" x2="14" y2="7"/><line x1="14" y1="21" x2="14" y2="26"/><line x1="2" y1="14" x2="7" y2="14"/><line x1="21" y1="14" x2="26" y2="14"/></g></svg>
         """#,
         expected: []),
]

// MARK: - No-harm probes (reported separately from the 35 held-out cases)
// Plain text whose only correct output is the text itself: each one targets a
// specific rule in ScriptRecovery / TextReflow that could damage ordinary text.

let noHarm: [Case] = [
    Case(id: "N01", area: .prose, desc: "no-harm: Georgia old-style figures in prose (5,140 / 31,705)", width: 700,
         css: "#cap{font-family:Georgia;font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>In 1848 the city had 5,140 inhabitants; by 1914 it had 31,705 and four railway stations.</p>"#,
         expected: ["In 1848 the city had 5,140 inhabitants; by 1914 it had 31,705 and four railway stations."]),

    Case(id: "N02", area: .prose, desc: "no-harm: percentages in Arial prose", width: 760,
         css: "#cap{font-family:Arial;font-size:16px;line-height:1.6} p{margin:0}",
         html: #"<p>Inflation fell from 7.4% to 2.1% in 2024, while unemployment stayed at 5.6% all year.</p>"#,
         expected: ["Inflation fell from 7.4% to 2.1% in 2024, while unemployment stayed at 5.6% all year."]),

    Case(id: "N03", area: .prose, desc: "no-harm: A0 / B0 paper sizes in a line with CO₂ and H₂O", width: 760,
         css: "#cap{font-family:Helvetica;font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>Use A0 sheets for the CO<sub>2</sub> poster and B0 sheets for the H<sub>2</sub>O one.</p>"#,
         expected: ["Use A0 sheets for the CO₂ poster and B0 sheets for the H₂O one."]),

    Case(id: "N04", area: .prose, desc: "no-harm: wrapped paragraph whose last line holds a subscript", width: 520,
         css: "#cap{font-family:'Times New Roman';font-size:18px;line-height:1.5} p{margin:0}",
         html: #"<p>When the limestone is heated strongly it decomposes into calcium oxide and releases carbon dioxide (CO<sub>2</sub>).</p>"#,
         expected: ["When the limestone is heated strongly it decomposes into calcium oxide and releases carbon dioxide (CO₂)."]),

    Case(id: "N05", area: .code, desc: "no-harm: C/Python with %, ** and # (Menlo, light)", width: 560,
         css: "pre{margin:0;font-family:Menlo;font-size:13px;line-height:1.5;color:#24292f} #cap{background:#f6f8fa;padding:16px 20px}",
         html: #"""
         <pre>printf("%d%%\n", 100);
         area = r ** 2 * 3.14  # r squared
         rate = 0.05  # 5% per year</pre>
         """#,
         expected: [#"""
         printf("%d%%\n", 100);
         area = r ** 2 * 3.14  # r squared
         rate = 0.05  # 5% per year
         """#, #"""
         printf("%d%%\n", 100);
         area = r ** 2 * 3.14 # r squared
         rate = 0.05 # 5% per year
         """#], keepBlankLines: true),

    Case(id: "N06", area: .prose, desc: "no-harm: possessives, plurals, it's, James's (Georgia)", width: 700,
         css: "#cap{font-family:Georgia;font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>The students’ results beat the 1990s’ averages; it’s James’s notebook, not the teachers’.</p>"#,
         expected: ["The students’ results beat the 1990s’ averages; it’s James’s notebook, not the teachers’."]),
]
