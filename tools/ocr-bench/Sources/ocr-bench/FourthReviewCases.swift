// Held-out cases for the fourth independent review (speed + accuracy,
// docs/reviews/2026-09-29-ocr-speed-review.md). Written, with their ground truth, BEFORE any
// output for them was looked at. A realistic IB (International Baccalaureate) student mix: physics /
// chemistry / maths formulas, essays and notes, lab methods, code, tables, UI and slides.
// W26–W30 are no-harm probes: ordinary text the math/code layers must leave alone.

private let stixW = "#cap{font-family:'STIX Two Text';font-size:30px} math[display=block]{margin:6px 0}"
private let gridW = "table{border-collapse:collapse} td,th{border:1px solid #999;padding:7px 14px;text-align:left} th{background:#eef}"

/// Every combination of the accepted spellings of each slot.
private func wcombos(_ template: String, _ slots: [(String, [String])]) -> [String] {
    var out = [template]
    for (slot, options) in slots {
        out = out.flatMap { s -> [String] in
            guard s.contains(slot) else { return [s] }
            return options.map { s.replacingOccurrences(of: slot, with: $0) }
        }
    }
    return out
}

let fourthReview: [Case] = [
    // MARK: Math (9)

    Case(id: "W01", area: .math, desc: "physics data booklet: v² = u² + 2as, s = ut + ½at² (Arial 22, HTML sup)", width: 520,
         css: "#cap{font-family:Arial;font-size:22px} p{margin:0 0 12px}",
         html: #"<p><i>v</i><sup>2</sup> = <i>u</i><sup>2</sup> + 2<i>as</i></p><p><i>s</i> = <i>ut</i> + ½<i>at</i><sup>2</sup></p>"#,
         expected: wcombos("v² = u² + 2as\ns = ut + HALFat²", [("HALF", ["½", "1/2", "(1/2)"])]), mode: .ignoreSpaces),

    Case(id: "W02", area: .math, desc: "chemistry: equilibrium constant K_c as a stacked fraction of bracketed concentrations", fit: true, css: stixW,
         html: #"<math display="block"><msub><mi>K</mi><mi>c</mi></msub><mo>=</mo><mfrac><msup><mrow><mo>[</mo><msub><mi mathvariant="normal">NH</mi><mn>3</mn></msub><mo>]</mo></mrow><mn>2</mn></msup><mrow><mo>[</mo><msub><mi mathvariant="normal">N</mi><mn>2</mn></msub><mo>]</mo><msup><mrow><mo>[</mo><msub><mi mathvariant="normal">H</mi><mn>2</mn></msub><mo>]</mo></mrow><mn>3</mn></msup></mrow></mfrac></math>"#,
         expected: ["K_c = [NH₃]²/([N₂][H₂]³)", "K_c = [NH₃]²/[N₂][H₂]³"], mode: .ignoreSpaces),

    Case(id: "W03", area: .math, desc: "compound interest sentence with an italic exponent n (Verdana 16)", width: 760,
         css: "#cap{font-family:Verdana;font-size:16px;line-height:1.7} p{margin:0}",
         html: #"<p>The future value is <i>FV</i> = <i>PV</i> × (1 + <i>r</i>/100)<sup><i>n</i></sup>, where <i>n</i> is the number of years.</p>"#,
         expected: ["The future value is FV = PV × (1 + r/100)ⁿ, where n is the number of years."], mode: .ignoreSpaces),

    Case(id: "W04", area: .math, desc: "chain rule: three stacked Leibniz fractions with ×", fit: true, css: stixW,
         html: #"<math display="block"><mfrac><mrow><mi>d</mi><mi>y</mi></mrow><mrow><mi>d</mi><mi>x</mi></mrow></mfrac><mo>=</mo><mfrac><mrow><mi>d</mi><mi>y</mi></mrow><mrow><mi>d</mi><mi>u</mi></mrow></mfrac><mo>×</mo><mfrac><mrow><mi>d</mi><mi>u</mi></mrow><mrow><mi>d</mi><mi>x</mi></mrow></mfrac></math>"#,
         expected: ["dy/dx = dy/du × du/dx"], mode: .ignoreSpaces),

    Case(id: "W05", area: .math, desc: "standardising a normal variable: Z = (X − μ)/σ", fit: true, css: stixW,
         html: #"<math display="block"><mi>Z</mi><mo>=</mo><mfrac><mrow><mi>X</mi><mo>−</mo><mi>μ</mi></mrow><mi>σ</mi></mfrac></math>"#,
         expected: ["Z = (X − μ)/σ"], mode: .ignoreSpaces),

    Case(id: "W06", area: .math, desc: "quadratic roots in a sentence (Georgia 18)", width: 760,
         css: "#cap{font-family:Georgia;font-size:18px;line-height:1.7} p{margin:0}",
         html: #"<p>The roots of 2<i>x</i><sup>2</sup> − 5<i>x</i> + 3 = 0 are <i>x</i> = 1 and <i>x</i> = 3/2.</p>"#,
         expected: ["The roots of 2x² − 5x + 3 = 0 are x = 1 and x = 3/2."], mode: .ignoreSpaces),

    Case(id: "W07", area: .math, desc: "definite integral of sin x from 0 to π", fit: true, css: stixW,
         html: #"<math display="block"><msubsup><mo>∫</mo><mn>0</mn><mi>π</mi></msubsup><mi>sin</mi><mi>x</mi><mspace width="0.2em"/><mi>d</mi><mi>x</mi><mo>=</mo><mn>2</mn></math>"#,
         expected: ["∫₀^π sin x dx = 2", "∫₀^(π) sin x dx = 2"], mode: .ignoreSpaces),

    Case(id: "W08", area: .math, desc: "arithmetic sequence: uₙ and Sₙ = n/2 (2u₁ + (n − 1)d)", fit: true, css: stixW,
         html: #"""
         <math display="block"><msub><mi>u</mi><mi>n</mi></msub><mo>=</mo><msub><mi>u</mi><mn>1</mn></msub><mo>+</mo><mo stretchy="false">(</mo><mi>n</mi><mo>−</mo><mn>1</mn><mo stretchy="false">)</mo><mi>d</mi></math>
         <math display="block"><msub><mi>S</mi><mi>n</mi></msub><mo>=</mo><mfrac><mi>n</mi><mn>2</mn></mfrac><mo stretchy="false">(</mo><mn>2</mn><msub><mi>u</mi><mn>1</mn></msub><mo>+</mo><mo stretchy="false">(</mo><mi>n</mi><mo>−</mo><mn>1</mn><mo stretchy="false">)</mo><mi>d</mi><mo stretchy="false">)</mo></math>
         """#,
         expected: wcombos("uₙ = u₁ + (n − 1)d\nSₙ = HALF(2u₁ + (n − 1)d)", [("HALF", ["n/2", "(n/2)"])]), mode: .ignoreSpaces),

    Case(id: "W09", area: .math, desc: "1x: physical constants with negative unit exponents (Helvetica 13)", density: 1, width: 560,
         css: "#cap{font-family:Helvetica;font-size:13px;line-height:1.6} p{margin:0}",
         html: #"<p>Take <i>g</i> = 9.81 m s<sup>−2</sup> and <i>c</i> = 3.00 × 10<sup>8</sup> m s<sup>−1</sup>.</p>"#,
         expected: ["Take g = 9.81 m s⁻² and c = 3.00 × 10⁸ m s⁻¹."], mode: .ignoreSpaces),

    // MARK: Prose (5)

    Case(id: "W10", area: .prose, desc: "TOK notes: heading + two paragraphs (Baskerville 19)", width: 720,
         css: "#cap{font-family:Baskerville;padding:32px 40px} h2{font-size:28px;margin:0 0 16px} p{font-size:19px;line-height:1.45;margin:0 0 14px}",
         html: #"""
         <h2>Knowledge and the Knower</h2>
         <p>Theory of Knowledge asks how we know what we claim to know. Rather than adding new facts, it invites students to examine the methods, assumptions and values that shape knowledge in each area.</p>
         <p>A strong essay links a clear knowledge question to specific real-life situations and considers counterclaims before reaching a conclusion.</p>
         """#,
         expected: ["Knowledge and the Knower\nTheory of Knowledge asks how we know what we claim to know. Rather than adding new facts, it invites students to examine the methods, assumptions and values that shape knowledge in each area.\nA strong essay links a clear knowledge question to specific real-life situations and considers counterclaims before reaching a conclusion."]),

    Case(id: "W11", area: .prose, desc: "literature: italic title, curly quotes, em dashes (Palatino 18)", width: 640,
         css: "#cap{font-family:Palatino;font-size:18px;line-height:1.55} p{margin:0}",
         html: #"<p>In <i>Hamlet</i>, the prince’s famous line — “To be, or not to be, that is the question” — opens a meditation on action and doubt.</p>"#,
         expected: ["In Hamlet, the prince's famous line — \"To be, or not to be, that is the question\" — opens a meditation on action and doubt."]),

    Case(id: "W12", area: .prose, desc: "economics definition with %, parentheses and PED = −0.5 (Helvetica Neue 17)", width: 700,
         css: "#cap{font-family:'Helvetica Neue';font-size:17px;line-height:1.5} p{margin:0}",
         html: #"<p>Price elasticity of demand (PED) measures how strongly quantity demanded responds to a change in price. If a 10% rise in price causes a 5% fall in quantity demanded, PED = −0.5 and demand is price inelastic.</p>"#,
         expected: ["Price elasticity of demand (PED) measures how strongly quantity demanded responds to a change in price. If a 10% rise in price causes a 5% fall in quantity demanded, PED = -0.5 and demand is price inelastic."]),

    Case(id: "W13", area: .prose, desc: "1x: short email to a teacher (Helvetica 13)", density: 1, width: 520,
         css: "#cap{font-family:Helvetica;font-size:13px;line-height:1.5} p{margin:0 0 10px}",
         html: #"""
         <p>Hi Ms. Ionescu,</p>
         <p>I have attached the second draft of my Extended Essay. Could you let me know by Friday whether the research question is focused enough?</p>
         <p>Thank you,<br>David</p>
         """#,
         expected: ["Hi Ms. Ionescu,\nI have attached the second draft of my Extended Essay. Could you let me know by Friday whether the research question is focused enough?\nThank you,\nDavid"]),

    Case(id: "W14", area: .prose, desc: "dark-mode notes app: title with em dash + paragraph (system-ui 16)", width: 600,
         css: "#cap{font-family:system-ui;background:#1e1e1e;color:#eaeaea;padding:28px} h3{font-size:20px;margin:0 0 12px} p{font-size:16px;line-height:1.5;margin:0}",
         html: #"""
         <h3>Biology HL — Unit 3 notes</h3>
         <p>Enzymes lower the activation energy of a reaction without being used up. Their activity depends on temperature, pH and substrate concentration.</p>
         """#,
         expected: ["Biology HL — Unit 3 notes\nEnzymes lower the activation energy of a reaction without being used up. Their activity depends on temperature, pH and substrate concentration."]),

    // MARK: Lists (2)

    Case(id: "W15", area: .lists, desc: "IA checklist: bullets with a nested hollow-bullet sublist (Helvetica 17)", width: 520,
         css: "#cap{font-family:Helvetica;font-size:17px;line-height:1.55} h4{font-size:19px;margin:0 0 8px} ul{margin:0;padding-left:26px} ul ul{list-style:circle}",
         html: #"""
         <h4>Internal Assessment checklist</h4>
         <ul><li>Research question stated clearly</li>
         <li>Variables identified<ul><li>independent</li><li>dependent</li><li>controlled</li></ul></li>
         <li>Raw data table with uncertainties</li></ul>
         """#,
         expected: indentVariants("Internal Assessment checklist\n• Research question stated clearly\n• Variables identified\n\t• independent\n\t• dependent\n\t• controlled\n• Raw data table with uncertainties")),

    Case(id: "W16", area: .lists, desc: "chemistry lab method: numbered steps with cm³ and mol dm⁻³ (Cochin 18)", width: 700,
         css: "#cap{font-family:Cochin;font-size:18px;line-height:1.55} h4{font-size:20px;margin:0 0 8px} ol{margin:0;padding-left:28px}",
         html: #"""
         <h4>Method</h4>
         <ol><li>Measure 50 cm<sup>3</sup> of 1.0 mol dm<sup>−3</sup> HCl into a conical flask.</li>
         <li>Add 2 g of calcium carbonate and start the stopwatch.</li>
         <li>Record the mass every 30 s for 5 minutes.</li></ol>
         """#,
         expected: ["Method\n1. Measure 50 cm³ of 1.0 mol dm⁻³ HCl into a conical flask.\n2. Add 2 g of calcium carbonate and start the stopwatch.\n3. Record the mass every 30 s for 5 minutes."]),

    // MARK: Code (3)

    Case(id: "W17", area: .code, desc: "IB CS: Python binary search, light editor (Menlo 14)", width: 560,
         css: "pre{margin:0;font-family:Menlo;font-size:14px;line-height:1.5;color:#1f2328} #cap{background:#f6f8fa;padding:16px 20px}",
         html: #"""
         <pre>def binary_search(arr, target):
             lo, hi = 0, len(arr) - 1
             while lo &lt;= hi:
                 mid = (lo + hi) // 2
                 if arr[mid] == target:
                     return mid
                 elif arr[mid] &lt; target:
                     lo = mid + 1
                 else:
                     hi = mid - 1
             return -1</pre>
         """#,
         expected: codeVariants("""
         def binary_search(arr, target):
             lo, hi = 0, len(arr) - 1
             while lo <= hi:
                 mid = (lo + hi) // 2
                 if arr[mid] == target:
                     return mid
                 elif arr[mid] < target:
                     lo = mid + 1
                 else:
                     hi = mid - 1
             return -1
         """), keepBlankLines: true),

    Case(id: "W18", area: .code, desc: "Java class with a blank line and a constructor (Courier New 15)", width: 600,
         css: "pre{margin:0;font-family:'Courier New';font-size:15px;line-height:1.45;color:#222} #cap{background:#fff;padding:16px 20px}",
         html: #"""
         <pre>public class Student {
             private String name;
             private int grade;

             public Student(String name, int grade) {
                 this.name = name;
                 this.grade = grade;
             }
         }</pre>
         """#,
         expected: codeVariants("""
         public class Student {
             private String name;
             private int grade;

             public Student(String name, int grade) {
                 this.name = name;
                 this.grade = grade;
             }
         }
         """), keepBlankLines: true),

    Case(id: "W19", area: .code, desc: "dark terminal: venv + pip install with a pinned version (Monaco 13)", width: 560,
         css: "pre{margin:0;font-family:Monaco;font-size:13px;line-height:1.5;color:#dddddd} #cap{background:#111;padding:14px 18px}",
         html: #"""
         <pre>$ python3 -m venv .venv
         $ source .venv/bin/activate
         (.venv) $ pip install numpy==1.26.4
         Successfully installed numpy-1.26.4</pre>
         """#,
         expected: ["$ python3 -m venv .venv\n$ source .venv/bin/activate\n(.venv) $ pip install numpy==1.26.4\nSuccessfully installed numpy-1.26.4"],
         keepBlankLines: true),

    // MARK: Tables (3)

    Case(id: "W20", area: .tables, desc: "bordered chemistry data table, 3 columns (Arial 16)", width: 560,
         css: "#cap{font-family:Arial;font-size:16px} " + gridW,
         html: #"""
         <table><tr><th>Element</th><th>Symbol</th><th>Relative atomic mass</th></tr>
         <tr><td>Hydrogen</td><td>H</td><td>1.01</td></tr>
         <tr><td>Carbon</td><td>C</td><td>12.01</td></tr>
         <tr><td>Oxygen</td><td>O</td><td>16.00</td></tr>
         <tr><td>Sodium</td><td>Na</td><td>22.99</td></tr></table>
         """#,
         expected: ["Element\tSymbol\tRelative atomic mass\nHydrogen\tH\t1.01\nCarbon\tC\t12.01\nOxygen\tO\t16.00\nSodium\tNa\t22.99"]),

    Case(id: "W21", area: .tables, desc: "borderless grade boundaries with en-dash ranges (Verdana 15)", width: 420,
         css: "#cap{font-family:Verdana;font-size:15px} table{border-collapse:collapse} th{text-align:left;padding:5px 24px 5px 0;border-bottom:2px solid #333} td{padding:5px 24px 5px 0}",
         html: #"""
         <table><tr><th>Grade</th><th>Boundary (%)</th></tr>
         <tr><td>7</td><td>80–100</td></tr>
         <tr><td>6</td><td>68–79</td></tr>
         <tr><td>5</td><td>56–67</td></tr>
         <tr><td>4</td><td>45–55</td></tr></table>
         """#,
         expected: wcombos("Grade\tBoundary (%)\n7\t80D100\n6\t68D79\n5\t56D67\n4\t45D55", [("D", ["–", "-"])])),

    Case(id: "W22", area: .tables, desc: "school timetable with empty cells (Helvetica Neue 14, bordered)", width: 560,
         css: "#cap{font-family:'Helvetica Neue';font-size:14px} " + gridW,
         html: #"""
         <table><tr><th>Time</th><th>Mon</th><th>Tue</th><th>Wed</th></tr>
         <tr><td>08:00</td><td>Maths HL</td><td></td><td>Physics</td></tr>
         <tr><td>09:30</td><td>English A</td><td>TOK</td><td></td></tr>
         <tr><td>11:00</td><td></td><td>Chemistry</td><td>Maths HL</td></tr></table>
         """#,
         expected: ["Time\tMon\tTue\tWed\n08:00\tMaths HL\t\tPhysics\n09:30\tEnglish A\tTOK\n11:00\t\tChemistry\tMaths HL",
                    "Time\tMon\tTue\tWed\n08:00\tMaths HL\t\tPhysics\n09:30\tEnglish A\tTOK\t\n11:00\t\tChemistry\tMaths HL"]),

    // MARK: UI and slides (3)

    Case(id: "W23", area: .math, desc: "slide: title + bullets with inline circle formulas, white on blue (Helvetica Neue)", width: 820,
         css: "#cap{font-family:'Helvetica Neue';background:#1d4e89;color:#fff;padding:40px 56px} h1{font-size:42px;margin:0 0 22px} ul{margin:0;padding-left:34px} li{font-size:28px;margin:0 0 10px}",
         html: #"""
         <h1>Circles</h1>
         <ul><li>Circumference: <i>C</i> = 2π<i>r</i></li>
         <li>Area: <i>A</i> = π<i>r</i><sup>2</sup></li>
         <li>Arc length: <i>l</i> = <i>r</i>θ</li></ul>
         """#,
         expected: ["Circles\n• Circumference: C = 2πr\n• Area: A = πr²\n• Arc length: l = rθ"], mode: .ignoreSpaces),

    Case(id: "W24", area: .layout, desc: "save dialog: bold question, explanation, three buttons in a row (system-ui)", width: 460,
         css: "#cap{font-family:system-ui;background:#ececec;padding:22px} .q{font-size:15px;font-weight:600;margin:0 0 8px} .e{font-size:13px;color:#333;margin:0 0 18px} .row{display:flex;gap:10px;justify-content:flex-end} .b{font-size:13px;background:#fff;border:1px solid #bbb;border-radius:6px;padding:4px 14px} .d{background:#2a6df4;color:#fff;border-color:#2a6df4}",
         html: #"""
         <p class="q">Do you want to save the changes you made to “IA draft”?</p>
         <p class="e">Your changes will be lost if you don’t save them.</p>
         <div class="row"><span class="b">Don’t Save</span><span class="b">Cancel</span><span class="b d">Save</span></div>
         """#,
         expected: wcombos("Do you want to save the changes you made to \"IA draft\"?\nYour changes will be lost if you don't save them.\nDon't SaveSEPCancelSEPSave", [("SEP", ["\t", " ", "\n"])])),

    Case(id: "W25", area: .layout, desc: "1x chat notification: sender left, time right, message below (Lucida Grande 13)", density: 1, width: 380,
         css: "#cap{font-family:'Lucida Grande';font-size:13px;background:#f4f4f6;padding:12px 14px} .h{display:flex;justify-content:space-between;font-weight:bold;margin-bottom:4px} .t{font-weight:normal;color:#666} p{margin:0}",
         html: #"""
         <div class="h"><span>Maria Popescu</span><span class="t">10:42</span></div>
         <p>Are we still meeting at 3 pm to go over the IA feedback?</p>
         """#,
         expected: wcombos("Maria PopescuSEP10:42\nAre we still meeting at 3 pm to go over the IA feedback?", [("SEP", ["\t", " ", "\n"])])),

    // MARK: No-harm (5) — plain text the math/code passes must not rewrite

    Case(id: "W26", area: .prose, desc: "no-harm: room number, plain '2nd', phone number, time (Georgia 17)", width: 700,
         css: "#cap{font-family:Georgia;font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>Room 204B is on the 2nd floor. Call 0721 555 019 before 9:30 to book it.</p>"#,
         expected: ["Room 204B is on the 2nd floor. Call 0721 555 019 before 9:30 to book it."]),

    Case(id: "W27", area: .prose, desc: "no-harm: in-text citation with et al., p. 42, Figure 3a (Times 17)", width: 720,
         css: "#cap{font-family:'Times New Roman';font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>Photosynthesis rates doubled under blue light (Smith et al., 2019, p. 42). See Figure 3a and Table 2.</p>"#,
         expected: ["Photosynthesis rates doubled under blue light (Smith et al., 2019, p. 42). See Figure 3a and Table 2."]),

    Case(id: "W28", area: .prose, desc: "no-harm: 'In', 'cost', 'sine', 'Log in' must not become math (Arial 17)", width: 720,
         css: "#cap{font-family:Arial;font-size:17px;line-height:1.6} p{margin:0}",
         html: #"<p>In the cost analysis, the sine of the angle was never needed. Log in to the portal to view it.</p>"#,
         expected: ["In the cost analysis, the sine of the angle was never needed. Log in to the portal to view it."]),

    Case(id: "W29", area: .prose, desc: "no-harm 1x: version number, date with slashes, issue numbers (Helvetica 13)", density: 1, width: 560,
         css: "#cap{font-family:Helvetica;font-size:13px;line-height:1.6} p{margin:0}",
         html: #"<p>Version 2.1.3 was released on 12/03/2026 and fixes issues #45 and #47.</p>"#,
         expected: ["Version 2.1.3 was released on 12/03/2026 and fixes issues #45 and #47."]),

    Case(id: "W30", area: .prose, desc: "no-harm: a command-line flag and a shortcut in prose (Verdana 15)", width: 720,
         css: "#cap{font-family:Verdana;font-size:15px;line-height:1.6} p{margin:0}",
         html: #"<p>Use the -v flag for verbose output, then press Ctrl+C to stop the server.</p>"#,
         expected: ["Use the -v flag for verbose output, then press Ctrl+C to stop the server."]),
]
