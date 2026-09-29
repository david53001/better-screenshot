// The corpus. Ground truth = what a careful human would retype (see README.md):
// paragraphs on one line, headings on their own line, list markers kept, code
// line-per-line with indentation, table cells separated by TABS, multi-column
// text in reading order, math as readable Unicode (x², xᵢ, (a + b)/2, √(x + 1)).

let cases: [Case] = prose + lists + code + tables + math + layout + robustness + heldOut + noHarm + thirdReview + gridCases

// MARK: - Prose

let prose: [Case] = [
    Case(id: "P01", area: .prose, desc: "lecture slide: heading + two wrapped paragraphs", width: 960,
         css: "#cap{font-family:'Helvetica Neue';padding:48px 56px} h1{font-size:44px;margin:0 0 28px} p{font-size:28px;line-height:1.35;margin:0 0 20px}",
         html: #"""
         <h1>Market Structures</h1>
         <p>A monopoly exists when a single firm supplies the entire market and there are high barriers to entry that prevent new firms from competing.</p>
         <p>Examples include local water utilities and patented pharmaceuticals.</p>
         """#,
         expected: ["""
         Market Structures
         A monopoly exists when a single firm supplies the entire market and there are high barriers to entry that prevent new firms from competing.
         Examples include local water utilities and patented pharmaceuticals.
         """]),

    Case(id: "P02", area: .prose, desc: "web article: heading + 3 paragraphs (Georgia 17)", width: 700,
         css: "#cap{font-family:Georgia;font-size:17px;line-height:1.55} h2{font-size:28px;margin:0 0 14px} p{margin:0 0 16px}",
         html: #"""
         <h2>Why the Ocean Is Salty</h2>
         <p>Rain is slightly acidic, so as it falls on land it slowly dissolves rocks and minerals. Rivers carry these dissolved salts to the sea, where they accumulate over millions of years.</p>
         <p>Evaporation removes water but leaves the salt behind, which is why the concentration stays high. Hydrothermal vents on the sea floor add further minerals.</p>
         <p>Today the average salinity of seawater is about 35 grams per kilogram.</p>
         """#,
         expected: ["""
         Why the Ocean Is Salty
         Rain is slightly acidic, so as it falls on land it slowly dissolves rocks and minerals. Rivers carry these dissolved salts to the sea, where they accumulate over millions of years.
         Evaporation removes water but leaves the salt behind, which is why the concentration stays high. Hydrothermal vents on the sea floor add further minerals.
         Today the average salinity of seawater is about 35 grams per kilogram.
         """]),

    Case(id: "P03", area: .prose, desc: "justified, auto-hyphenated narrow column (Times 15)", width: 330,
         css: "#cap{font-family:'Times New Roman';font-size:15px;line-height:1.4;text-align:justify;-webkit-hyphens:auto;hyphens:auto}",
         html: #"""
         <p style="margin:0">Photosynthesis converts light energy into chemical energy stored in glucose. The light-dependent reactions take place in the thylakoid membranes, while the Calvin cycle operates in the stroma of the chloroplast.</p>
         """#,
         expected: ["Photosynthesis converts light energy into chemical energy stored in glucose. The light-dependent reactions take place in the thylakoid membranes, while the Calvin cycle operates in the stroma of the chloroplast."]),

    Case(id: "P04", area: .prose, desc: "1x external monitor: web text Helvetica 14", density: 1, width: 600,
         css: "#cap{font-family:Helvetica;font-size:14px;line-height:1.45} h3{font-size:18px;margin:0 0 8px} p{margin:0 0 10px}",
         html: #"""
         <h3>Opening hours</h3>
         <p>The library is open from 8:00 to 18:00 on weekdays and from 10:00 to 14:00 on Saturdays. During exam season, the reading room stays open until 21:00.</p>
         <p>Please return borrowed books within 14 days.</p>
         """#,
         expected: ["""
         Opening hours
         The library is open from 8:00 to 18:00 on weekdays and from 10:00 to 14:00 on Saturdays. During exam season, the reading room stays open until 21:00.
         Please return borrowed books within 14 days.
         """]),

    Case(id: "P05", area: .prose, desc: "mixed font sizes: title, subtitle, body, caption", width: 760,
         css: "#cap{font-family:'Helvetica Neue'} .t{font-size:34px;font-weight:700} .s{font-size:20px;color:#666;margin-top:6px} p{font-size:16px;line-height:1.5;margin:14px 0} .c{font-size:12px;font-style:italic;color:#555}",
         html: #"""
         <div class="t">Cell Division</div>
         <div class="s">Mitosis and meiosis compared</div>
         <p>Mitosis produces two genetically identical diploid cells and is used for growth and repair. Meiosis produces four genetically different haploid gametes.</p>
         <div class="c">Source: IB Biology Course Companion, chapter 1.6</div>
         """#,
         expected: ["""
         Cell Division
         Mitosis and meiosis compared
         Mitosis produces two genetically identical diploid cells and is used for growth and repair. Meiosis produces four genetically different haploid gametes.
         Source: IB Biology Course Companion, chapter 1.6
         """]),

    Case(id: "P06", area: .prose, desc: "book-style paragraphs: first-line indent, no gap", width: 520,
         css: "#cap{font-family:'Times New Roman';font-size:17px;line-height:1.45} p{margin:0;text-indent:1.5em;text-align:justify}",
         html: #"""
         <p>It was late in the afternoon when the train finally pulled into the station. Maria gathered her bags and stepped onto the empty platform, where the air smelled of rain and coal smoke.</p>
         <p>Nobody had come to meet her. She checked the letter again, reading the address twice, and then set off towards the town.</p>
         <p>The streets were quiet and the shops had already closed.</p>
         """#,
         expected: ["""
         It was late in the afternoon when the train finally pulled into the station. Maria gathered her bags and stepped onto the empty platform, where the air smelled of rain and coal smoke.
         Nobody had come to meet her. She checked the letter again, reading the address twice, and then set off towards the town.
         The streets were quiet and the shops had already closed.
         """]),
]

// MARK: - Lists

let lists: [Case] = [
    Case(id: "L01", area: .lists, desc: "slide bullets, items wrap", width: 960,
         css: "#cap{font-family:'Helvetica Neue';padding:44px 56px} h1{font-size:40px;margin:0 0 20px} ul{font-size:28px;line-height:1.35;margin:0;padding-left:40px} li{margin-bottom:12px}",
         html: #"""
         <h1>Causes of World War I</h1>
         <ul>
         <li>Militarism: the major powers built up large armies and navies in an arms race before 1914</li>
         <li>Alliances divided Europe into two armed camps</li>
         <li>Imperialism created rivalry over colonies and trade routes in Africa and Asia</li>
         <li>Nationalism</li>
         </ul>
         """#,
         expected: ["""
         Causes of World War I
         • Militarism: the major powers built up large armies and navies in an arms race before 1914
         • Alliances divided Europe into two armed camps
         • Imperialism created rivalry over colonies and trade routes in Africa and Asia
         • Nationalism
         """]),

    Case(id: "L02", area: .lists, desc: "numbered list (doc), items wrap", width: 620,
         css: "#cap{font-family:Georgia;font-size:16px;line-height:1.5} p{margin:0 0 8px;font-weight:bold} ol{margin:0;padding-left:28px} li{margin-bottom:6px}",
         html: #"""
         <p>Method</p>
         <ol>
         <li>Measure 50 ml of hydrochloric acid into a conical flask using a measuring cylinder.</li>
         <li>Add a 3 cm strip of magnesium ribbon and start the stopwatch immediately.</li>
         <li>Record the time taken for the ribbon to disappear completely.</li>
         <li>Repeat the experiment at four different temperatures.</li>
         </ol>
         """#,
         expected: ["""
         Method
         1. Measure 50 ml of hydrochloric acid into a conical flask using a measuring cylinder.
         2. Add a 3 cm strip of magnesium ribbon and start the stopwatch immediately.
         3. Record the time taken for the ribbon to disappear completely.
         4. Repeat the experiment at four different temperatures.
         """]),

    Case(id: "L03", area: .lists, desc: "nested list, 3 levels (disc/circle/square)", width: 520,
         css: "#cap{font-family:Helvetica;font-size:17px;line-height:1.6} ul{margin:0;padding-left:30px}",
         html: #"""
         <ul style="list-style:disc"><li>Fruit<ul style="list-style:circle"><li>Apples</li><li>Pears<ul style="list-style:square"><li>Conference</li><li>Williams</li></ul></li></ul></li><li>Vegetables<ul style="list-style:circle"><li>Carrots</li></ul></li></ul>
         """#,
         expected: {
             let rendered = "• Fruit\n\t◦ Apples\n\t◦ Pears\n\t\t▪ Conference\n\t\t▪ Williams\n• Vegetables\n\t◦ Carrots"
             let bullets = "• Fruit\n\t• Apples\n\t• Pears\n\t\t• Conference\n\t\t• Williams\n• Vegetables\n\t• Carrots"
             let dashes = bullets.replacingOccurrences(of: "•", with: "-")
             return indentVariants(rendered) + indentVariants(bullets) + indentVariants(dashes)
         }()),

    Case(id: "L04", area: .lists, desc: "IB exam sub-parts (a)(b)(c) with marks [n] at right", width: 700,
         css: "#cap{font-family:'Times New Roman';font-size:17px;line-height:1.45} .row{display:flex;align-items:flex-end;margin:6px 0} .row .t{flex:1;padding-right:40px} .stem{margin-bottom:10px}",
         html: #"""
         <div class="stem">3. A survey asked 120 students how they travel to school.</div>
         <div class="row"><div class="t">(a) Write down the number of students who walk to school.</div><div>[1]</div></div>
         <div class="row"><div class="t">(b) Find the probability that a randomly chosen student travels by bus.</div><div>[2]</div></div>
         <div class="row"><div class="t">(c) Two students are chosen at random. Find the probability that both of them cycle to school.</div><div>[3]</div></div>
         """#,
         expected: tabOrSpace("""
         3. A survey asked 120 students how they travel to school.
         (a) Write down the number of students who walk to school.\t[1]
         (b) Find the probability that a randomly chosen student travels by bus.\t[2]
         (c) Two students are chosen at random. Find the probability that both of them cycle to school.\t[3]
         """)),

    Case(id: "L05", area: .lists, desc: "checklist with ballot-box glyphs", width: 520,
         css: "#cap{font-family:'Helvetica Neue';font-size:18px;line-height:1.8}",
         html: #"""
         <div>☐ Buy milk</div><div>☑ Call the dentist</div><div>☐ Finish the history essay draft</div><div>☑ Email Ms Popescu about the field trip</div>
         """#,
         expected: [
             "☐ Buy milk\n☑ Call the dentist\n☐ Finish the history essay draft\n☑ Email Ms Popescu about the field trip",
             "- [ ] Buy milk\n- [x] Call the dentist\n- [ ] Finish the history essay draft\n- [x] Email Ms Popescu about the field trip",
         ]),

    Case(id: "L06", area: .lists, desc: "1x: en-dash / asterisk plain-text list, one item wraps", density: 1, width: 520,
         css: "#cap{font-family:Helvetica;font-size:13px;line-height:1.5} .i{padding-left:1em;text-indent:-1em}",
         html: #"""
         <div>Packing list:</div>
         <div class="i">– Passport and printed boarding pass</div>
         <div class="i">– Phone charger, headphones and a universal travel adapter for European sockets</div>
         <div class="i">* Snacks for the flight</div>
         <div class="i">– Two pairs of comfortable walking shoes</div>
         """#,
         expected: ["""
         Packing list:
         – Passport and printed boarding pass
         – Phone charger, headphones and a universal travel adapter for European sockets
         * Snacks for the flight
         – Two pairs of comfortable walking shoes
         """]),
]

// MARK: - Code

private let darkPre = "pre{margin:0;font-family:Menlo;font-size:13px;line-height:1.5;color:#d4d4d4} #cap{background:#1e1e1e;padding:18px 22px} .k{color:#569cd6} .ty{color:#4ec9b0} .n{color:#b5cea8} .s{color:#ce9178} .c{color:#6a9955} .f{color:#dcdcaa}"
private let lightPre = "pre{margin:0;font-family:Menlo;font-size:13px;line-height:1.5;color:#24292f} #cap{background:#f6f8fa;padding:16px 20px} .k{color:#cf222e} .n{color:#0550ae} .s{color:#0a3069} .c{color:#6e7781} .f{color:#8250df}"

let code: [Case] = [
    Case(id: "C01", area: .code, desc: "Swift, dark editor theme, 4-space indent, blank lines", width: 640,
         css: darkPre,
         html: #"""
         <pre><span class="k">import</span> Foundation

         <span class="k">struct</span> <span class="ty">Student</span> {
             <span class="k">let</span> name: <span class="ty">String</span>
             <span class="k">var</span> grades: [<span class="ty">Int</span>]

             <span class="k">var</span> average: <span class="ty">Double</span> {
                 <span class="k">guard</span> !grades.isEmpty <span class="k">else</span> { <span class="k">return</span> <span class="n">0</span> }
                 <span class="k">return</span> <span class="ty">Double</span>(grades.reduce(<span class="n">0</span>, +)) / <span class="ty">Double</span>(grades.count)
             }
         }</pre>
         """#,
         expected: codeVariants("""
         import Foundation

         struct Student {
             let name: String
             var grades: [Int]

             var average: Double {
                 guard !grades.isEmpty else { return 0 }
                 return Double(grades.reduce(0, +)) / Double(grades.count)
             }
         }
         """), keepBlankLines: true),

    Case(id: "C02", area: .code, desc: "Python, light theme, nested indent, quotes, operators", width: 640,
         css: lightPre,
         html: #"""
         <pre><span class="k">def</span> <span class="f">grade</span>(score):
             <span class="c"># IB boundaries for Paper 1</span>
             <span class="k">if</span> score &gt;= <span class="n">80</span>:
                 <span class="k">return</span> <span class="s">"7"</span>
             <span class="k">elif</span> score &gt;= <span class="n">65</span> <span class="k">and</span> score != <span class="n">70</span>:
                 <span class="k">return</span> <span class="s">"6"</span>
             <span class="k">return</span> <span class="s">'below 6'</span>

         results = {name: grade(s) <span class="k">for</span> name, s <span class="k">in</span> scores.items()}
         print(<span class="s">f"{len(results)} students graded"</span>)</pre>
         """#,
         expected: codeVariants("""
         def grade(score):
             # IB boundaries for Paper 1
             if score >= 80:
                 return "7"
             elif score >= 65 and score != 70:
                 return "6"
             return 'below 6'

         results = {name: grade(s) for name, s in scores.items()}
         print(f"{len(results)} students graded")
         """), keepBlankLines: true),

    Case(id: "C03", area: .code, desc: "JavaScript, longest line first, 2-space indent, template literal", width: 700,
         css: lightPre,
         html: #"""
         <pre><span class="k">const</span> total = items.reduce((sum, item) =&gt; sum + item.price * item.qty, <span class="n">0</span>);
         <span class="k">if</span> (total === <span class="n">0</span>) {
           <span class="k">return</span> <span class="k">null</span>;
         }
         <span class="k">const</span> label = <span class="s">`Total: ${total.toFixed(2)} EUR`</span>;
         console.log(label);</pre>
         """#,
         expected: codeVariants("""
         const total = items.reduce((sum, item) => sum + item.price * item.qty, 0);
         if (total === 0) {
           return null;
         }
         const label = `Total: ${total.toFixed(2)} EUR`;
         console.log(label);
         """, unit: 2), keepBlankLines: true),

    Case(id: "C04", area: .code, desc: "terminal: Python traceback", width: 640,
         css: "pre{margin:0;font-family:Menlo;font-size:13px;line-height:1.45;color:#c5c8c6} #cap{background:#1d1f21;padding:14px 18px} .p{color:#b5bd68}",
         html: #"""
         <pre><span class="p">$</span> python3 main.py
         Traceback (most recent call last):
           File "main.py", line 3, in &lt;module&gt;
             print(total / count)
         ZeroDivisionError: division by zero
         <span class="p">$</span> echo $?
         1</pre>
         """#,
         expected: ["""
         $ python3 main.py
         Traceback (most recent call last):
           File "main.py", line 3, in <module>
             print(total / count)
         ZeroDivisionError: division by zero
         $ echo $?
         1
         """], keepBlankLines: true),

    Case(id: "C05", area: .code, desc: "code with a line-number gutter (GitHub style)", width: 600,
         css: "#cap{background:#fff;padding:12px 8px;font-family:Menlo;font-size:13px} table{border-collapse:collapse} td{padding:0 10px;line-height:1.6;white-space:pre} td.ln{color:#8c959f;text-align:right;border-right:1px solid #d0d7de;user-select:none} .k{color:#cf222e} .n{color:#0550ae} .c{color:#6e7781}",
         html: #"""
         <table>
         <tr><td class="ln">1</td><td><span class="k">function</span> fib(n) {</td></tr>
         <tr><td class="ln">2</td><td>  <span class="k">if</span> (n &lt; <span class="n">2</span>) <span class="k">return</span> n;</td></tr>
         <tr><td class="ln">3</td><td>  <span class="k">return</span> fib(n - <span class="n">1</span>) + fib(n - <span class="n">2</span>);</td></tr>
         <tr><td class="ln">4</td><td>}</td></tr>
         <tr><td class="ln">5</td><td> </td></tr>
         <tr><td class="ln">6</td><td>console.log(fib(<span class="n">10</span>)); <span class="c">// 55</span></td></tr>
         </table>
         """#,
         expected: codeVariants("""
         function fib(n) {
           if (n < 2) return n;
           return fib(n - 1) + fib(n - 2);
         }

         console.log(fib(10)); // 55
         """, unit: 2), keepBlankLines: true),

    Case(id: "C06", area: .code, desc: "1x: C, light theme, pointers and escapes", density: 1, width: 520,
         css: lightPre.replacingOccurrences(of: "font-size:13px", with: "font-size:12px"),
         html: #"""
         <pre><span class="k">#include</span> <span class="s">&lt;stdio.h&gt;</span>

         <span class="k">int</span> main(<span class="k">void</span>) {
             <span class="k">int</span> x = <span class="n">42</span>;
             <span class="k">int</span> *p = &amp;x;
             printf(<span class="s">"%d\n"</span>, *p);
             <span class="k">return</span> <span class="n">0</span>;
         }</pre>
         """#,
         expected: codeVariants(#"""
         #include <stdio.h>

         int main(void) {
             int x = 42;
             int *p = &x;
             printf("%d\n", *p);
             return 0;
         }
         """#), keepBlankLines: true),

    Case(id: "C07", area: .code, desc: "YAML (GitHub Actions), semantic indentation", width: 560,
         css: darkPre,
         html: #"""
         <pre><span class="k">name</span>: CI
         <span class="k">on</span>: [push, pull_request]
         <span class="k">jobs</span>:
           <span class="k">build</span>:
             <span class="k">runs-on</span>: macos-15
             <span class="k">steps</span>:
               - <span class="k">uses</span>: actions/checkout@v4
               - <span class="k">name</span>: Run tests
                 <span class="k">run</span>: swift test --parallel</pre>
         """#,
         expected: ["""
         name: CI
         on: [push, pull_request]
         jobs:
           build:
             runs-on: macos-15
             steps:
               - uses: actions/checkout@v4
               - name: Run tests
                 run: swift test --parallel
         """], keepBlankLines: true),

    Case(id: "C08", area: .code, desc: "shell one-liners with regex, globs, flags", width: 820,
         css: "pre{margin:0;font-family:Menlo;font-size:13px;line-height:1.6;color:#e6e6e6} #cap{background:#282c34;padding:14px 18px}",
         html: #"""
         <pre>$ grep -rnE '^[a-z_]+\(' src/ | sort -u &gt; funcs.txt
         $ find . -name "*.log" -mtime +7 -delete
         $ curl -fsSL https://example.com/install.sh | bash -s -- --prefix=$HOME/.local</pre>
         """#,
         expected: [#"""
         $ grep -rnE '^[a-z_]+\(' src/ | sort -u > funcs.txt
         $ find . -name "*.log" -mtime +7 -delete
         $ curl -fsSL https://example.com/install.sh | bash -s -- --prefix=$HOME/.local
         """#], keepBlankLines: true),
]

// MARK: - Tables

private let gridTable = "table{border-collapse:collapse} td,th{border:1px solid #bbb;padding:8px 14px;text-align:left} th{background:#f0f0f0}"

let tables: [Case] = [
    Case(id: "T01", area: .tables, desc: "simple bordered grid with header row", width: 560,
         css: "#cap{font-family:Helvetica;font-size:16px} " + gridTable,
         html: #"""
         <table><tr><th>Country</th><th>Capital</th><th>Population (M)</th></tr>
         <tr><td>Romania</td><td>Bucharest</td><td>19.0</td></tr>
         <tr><td>Hungary</td><td>Budapest</td><td>9.6</td></tr>
         <tr><td>Bulgaria</td><td>Sofia</td><td>6.4</td></tr></table>
         """#,
         expected: ["Country\tCapital\tPopulation (M)\nRomania\tBucharest\t19.0\nHungary\tBudapest\t9.6\nBulgaria\tSofia\t6.4"]),

    Case(id: "T02", area: .tables, desc: "invoice: right-aligned numeric columns, empty cells in total row", width: 620,
         css: "#cap{font-family:Helvetica;font-size:15px} table{border-collapse:collapse;width:100%} th{border-bottom:2px solid #333;text-align:left;padding:6px 10px} td{padding:6px 10px;border-bottom:1px solid #ddd} .r{text-align:right} tr.tot td{font-weight:bold;border-top:2px solid #333}",
         html: #"""
         <table><tr><th>Item</th><th class="r">Qty</th><th class="r">Unit price</th><th class="r">Total</th></tr>
         <tr><td>Notebook</td><td class="r">3</td><td class="r">2.50</td><td class="r">7.50</td></tr>
         <tr><td>Graphing calculator</td><td class="r">1</td><td class="r">119.00</td><td class="r">119.00</td></tr>
         <tr><td>Pens (pack of 10)</td><td class="r">2</td><td class="r">4.25</td><td class="r">8.50</td></tr>
         <tr class="tot"><td>Total</td><td></td><td></td><td class="r">135.00</td></tr></table>
         """#,
         expected: ["Item\tQty\tUnit price\tTotal\nNotebook\t3\t2.50\t7.50\nGraphing calculator\t1\t119.00\t119.00\nPens (pack of 10)\t2\t4.25\t8.50\nTotal\t\t\t135.00"]),

    Case(id: "T03", area: .tables, desc: "spreadsheet look: gridlines, Arial 13, decimals", width: 620,
         css: "#cap{font-family:Arial;font-size:13px;padding:10px} table{border-collapse:collapse} td{border:1px solid #d0d0d0;padding:4px 10px;min-width:48px} tr:first-child td{background:#f3f3f3;font-weight:bold} td.r{text-align:right}",
         html: #"""
         <table><tr><td>Student</td><td>Test 1</td><td>Test 2</td><td>Test 3</td><td>Average</td></tr>
         <tr><td>Ana Ionescu</td><td class="r">78</td><td class="r">85</td><td class="r">91</td><td class="r">84.7</td></tr>
         <tr><td>Mihai Popa</td><td class="r">64</td><td class="r">70</td><td class="r">68</td><td class="r">67.3</td></tr>
         <tr><td>Elena Dumitru</td><td class="r">92</td><td class="r">88</td><td class="r">95</td><td class="r">91.7</td></tr>
         <tr><td>Andrei Stan</td><td class="r">55</td><td class="r">61</td><td class="r">73</td><td class="r">63.0</td></tr></table>
         """#,
         expected: ["Student\tTest 1\tTest 2\tTest 3\tAverage\nAna Ionescu\t78\t85\t91\t84.7\nMihai Popa\t64\t70\t68\t67.3\nElena Dumitru\t92\t88\t95\t91.7\nAndrei Stan\t55\t61\t73\t63.0"]),

    Case(id: "T04", area: .tables, desc: "ragged: empty cells + a cell that wraps to two lines", width: 680,
         css: "#cap{font-family:Helvetica;font-size:15px} " + gridTable + " td.w{width:210px}",
         html: #"""
         <table><tr><th>Task</th><th>Owner</th><th>Due</th><th>Notes</th></tr>
         <tr><td>Collect survey data</td><td>Ana</td><td>12 Oct</td><td class="w">Use the Google Form link from the class page</td></tr>
         <tr><td>Write introduction</td><td></td><td>15 Oct</td><td class="w"></td></tr>
         <tr><td>Make graphs</td><td>Mihai</td><td></td><td class="w">Bar charts only</td></tr></table>
         """#,
         expected: ["Task\tOwner\tDue\tNotes\nCollect survey data\tAna\t12 Oct\tUse the Google Form link from the class page\nWrite introduction\t\t15 Oct\nMake graphs\tMihai\t\tBar charts only"]),

    Case(id: "T05", area: .tables, desc: "borderless timetable (whitespace-aligned columns)", width: 620,
         css: "#cap{font-family:Helvetica;font-size:15px} td{padding:6px 22px 6px 0} tr:first-child td{font-weight:bold}",
         html: #"""
         <table><tr><td>Time</td><td>Monday</td><td>Tuesday</td><td>Wednesday</td></tr>
         <tr><td>08:00</td><td>Maths</td><td>English</td><td>Physics</td></tr>
         <tr><td>09:30</td><td>Biology</td><td>Maths</td><td>History</td></tr>
         <tr><td>11:00</td><td>Chemistry</td><td>Art</td><td>Maths</td></tr></table>
         """#,
         expected: ["Time\tMonday\tTuesday\tWednesday\n08:00\tMaths\tEnglish\tPhysics\n09:30\tBiology\tMaths\tHistory\n11:00\tChemistry\tArt\tMaths"]),

    Case(id: "T06", area: .tables, desc: "comparison table with multi-line text cells", width: 720,
         css: "#cap{font-family:Georgia;font-size:15px;line-height:1.4} " + gridTable + " td{width:200px;vertical-align:top}",
         html: #"""
         <table><tr><th>Feature</th><th>Mitosis</th><th>Meiosis</th></tr>
         <tr><td>Number of divisions</td><td>One</td><td>Two</td></tr>
         <tr><td>Daughter cells produced</td><td>Two diploid cells</td><td>Four haploid cells</td></tr>
         <tr><td>Genetic variation</td><td>None, the cells are identical clones</td><td>Crossing over and independent assortment</td></tr></table>
         """#,
         expected: ["Feature\tMitosis\tMeiosis\nNumber of divisions\tOne\tTwo\nDaughter cells produced\tTwo diploid cells\tFour haploid cells\nGenetic variation\tNone, the cells are identical clones\tCrossing over and independent assortment"]),

    Case(id: "T07", area: .tables, desc: "1x: small bordered table (12 px)", density: 1, width: 440,
         css: "#cap{font-family:Helvetica;font-size:12px} table{border-collapse:collapse} td,th{border:1px solid #bbb;padding:4px 10px;text-align:left} th{background:#f0f0f0}",
         html: #"""
         <table><tr><th>Symbol</th><th>Quantity</th><th>SI unit</th></tr>
         <tr><td>F</td><td>force</td><td>N</td></tr>
         <tr><td>E</td><td>energy</td><td>J</td></tr>
         <tr><td>P</td><td>power</td><td>W</td></tr>
         <tr><td>v</td><td>velocity</td><td>m/s</td></tr></table>
         """#,
         expected: ["Symbol\tQuantity\tSI unit\nF\tforce\tN\nE\tenergy\tJ\nP\tpower\tW\nv\tvelocity\tm/s"]),
]

// MARK: - Math (MathML rendered natively by WebKit in STIX Two Math, unless noted)

private let mathCSS = "#cap{font-family:'STIX Two Text';font-size:30px} math[display=block]{margin:6px 0}"

let math: [Case] = [
    Case(id: "M01", area: .math, desc: "slide: E = mc²", fit: true, css: "#cap{font-size:48px;padding:30px}",
         html: #"<math display="block"><mi>E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></math>"#,
         expected: ["E = mc²"], mode: .ignoreSpaces),

    Case(id: "M02", area: .math, desc: "display: x² + y² = z²", fit: true, css: mathCSS,
         html: #"<math display="block"><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><msup><mi>y</mi><mn>2</mn></msup><mo>=</mo><msup><mi>z</mi><mn>2</mn></msup></math>"#,
         expected: ["x² + y² = z²"], mode: .ignoreSpaces),

    Case(id: "M03", area: .math, desc: "inline math in prose: A = πr²", width: 720,
         css: "#cap{font-family:Georgia;font-size:18px;line-height:1.6} p{margin:0}",
         html: #"<p>The area of a circle is <math><mi>A</mi><mo>=</mo><mi>π</mi><msup><mi>r</mi><mn>2</mn></msup></math>, so doubling <math><mi>r</mi></math> multiplies the area by 4.</p>"#,
         expected: ["The area of a circle is A = πr², so doubling r multiplies the area by 4."]),

    Case(id: "M04", area: .math, desc: "quadratic formula (stacked fraction + root)", fit: true, css: mathCSS,
         html: #"<math display="block"><mi>x</mi><mo>=</mo><mfrac><mrow><mo>−</mo><mi>b</mi><mo>±</mo><msqrt><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></msqrt></mrow><mrow><mn>2</mn><mi>a</mi></mrow></mfrac></math>"#,
         expected: ["x = (−b ± √(b² − 4ac))/(2a)", "x = (−b ± √(b² − 4ac))/2a"], mode: .ignoreSpaces),

    Case(id: "M05", area: .math, desc: "stacked fraction: m = (a + b)/2", fit: true, css: mathCSS,
         html: #"<math display="block"><mi>m</mi><mo>=</mo><mfrac><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mn>2</mn></mfrac></math>"#,
         expected: ["m = (a + b)/2"], mode: .ignoreSpaces),

    Case(id: "M06", area: .math, desc: "subscripts: arithmetic sequence (IB)", fit: true, css: mathCSS,
         html: #"""
         <math display="block"><msub><mi>a</mi><mi>n</mi></msub><mo>=</mo><msub><mi>a</mi><mn>1</mn></msub><mo>+</mo><mo>(</mo><mi>n</mi><mo>−</mo><mn>1</mn><mo>)</mo><mi>d</mi></math>
         <math display="block"><msub><mi>S</mi><mi>n</mi></msub><mo>=</mo><mfrac><mi>n</mi><mn>2</mn></mfrac><mo>(</mo><mn>2</mn><msub><mi>a</mi><mn>1</mn></msub><mo>+</mo><mo>(</mo><mi>n</mi><mo>−</mo><mn>1</mn><mo>)</mo><mi>d</mi><mo>)</mo></math>
         """#,
         expected: ["aₙ = a₁ + (n − 1)d\nSₙ = n/2 (2a₁ + (n − 1)d)", "aₙ = a₁ + (n − 1)d\nSₙ = (n/2)(2a₁ + (n − 1)d)"], mode: .ignoreSpaces),

    Case(id: "M07", area: .math, desc: "square root and cube root", fit: true, css: mathCSS,
         html: #"""
         <math display="block"><msqrt><mi>x</mi><mo>+</mo><mn>1</mn></msqrt><mo>=</mo><mn>3</mn></math>
         <math display="block"><mroot><mn>8</mn><mn>3</mn></mroot><mo>=</mo><mn>2</mn></math>
         """#,
         expected: ["√(x + 1) = 3\n∛8 = 2", "√(x + 1) = 3\n³√8 = 2"], mode: .ignoreSpaces),

    Case(id: "M08", area: .math, desc: "definite integral with limits", fit: true, css: mathCSS,
         html: #"<math display="block"><msubsup><mo>∫</mo><mn>0</mn><mn>1</mn></msubsup><msup><mi>x</mi><mn>2</mn></msup><mspace width="0.2em"/><mi>d</mi><mi>x</mi><mo>=</mo><mfrac><mn>1</mn><mn>3</mn></mfrac></math>"#,
         expected: ["∫₀¹ x² dx = 1/3", "∫₀¹ x² dx = ⅓"], mode: .ignoreSpaces),

    Case(id: "M09", area: .math, desc: "sum with limits above/below", fit: true, css: mathCSS,
         html: #"<math display="block"><munderover><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><mi>i</mi><mo>=</mo><mfrac><mrow><mi>n</mi><mo>(</mo><mi>n</mi><mo>+</mo><mn>1</mn><mo>)</mo></mrow><mn>2</mn></mfrac></math>"#,
         expected: ["∑ᵢ₌₁ⁿ i = n(n + 1)/2", "∑_(i=1)^n i = n(n + 1)/2"], mode: .ignoreSpaces),

    Case(id: "M10", area: .math, desc: "Greek + logic: epsilon-delta definition", fit: true, css: mathCSS.replacingOccurrences(of: "30px", with: "26px"),
         html: #"<math display="block"><mo>∀</mo><mi>ε</mi><mo>&gt;</mo><mn>0</mn><mspace width="0.5em"/><mo>∃</mo><mi>δ</mi><mo>&gt;</mo><mn>0</mn><mo>:</mo><mspace width="0.3em"/><mo>|</mo><mi>x</mi><mo>−</mo><mi>a</mi><mo>|</mo><mo>&lt;</mo><mi>δ</mi><mo>⇒</mo><mo>|</mo><mi>f</mi><mo>(</mo><mi>x</mi><mo>)</mo><mo>−</mo><mi>L</mi><mo>|</mo><mo>&lt;</mo><mi>ε</mi></math>"#,
         expected: ["∀ε > 0 ∃δ > 0: |x − a| < δ ⇒ |f(x) − L| < ε"], mode: .ignoreSpaces),

    Case(id: "M11", area: .math, desc: "relation/operator symbols", fit: true, css: mathCSS.replacingOccurrences(of: "30px", with: "26px"),
         html: #"<math display="block"><mi>a</mi><mo>≤</mo><mi>b</mi><mo>,</mo><mi>c</mi><mo>≥</mo><mi>d</mi><mo>,</mo><mi>x</mi><mo>≠</mo><mi>y</mi><mo>,</mo><mn>3</mn><mo>±</mo><mn>0.5</mn><mo>,</mo><mn>6</mn><mo>×</mo><mn>7</mn><mo>÷</mo><mn>2</mn><mo>,</mo><mi>x</mi><mo>→</mo><mi>∞</mi><mo>,</mo><mi>x</mi><mo>∈</mo><mi>ℝ</mi></math>"#,
         expected: ["a ≤ b, c ≥ d, x ≠ y, 3 ± 0.5, 6 × 7 ÷ 2, x → ∞, x ∈ ℝ"], mode: .ignoreSpaces),

    Case(id: "M12", area: .math, desc: "2×2 matrix in brackets + determinant", fit: true, css: mathCSS,
         html: #"""
         <math display="block"><mi>A</mi><mo>=</mo><mrow><mo>[</mo><mtable><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></mtable><mo>]</mo></mrow></math>
         <math display="block"><mi>det</mi><mi>A</mi><mo>=</mo><mo>−</mo><mn>2</mn></math>
         """#,
         expected: ["A = [1 2; 3 4]\ndet A = −2", "A = [[1, 2], [3, 4]]\ndet A = −2", "A = (1 2; 3 4)\ndet A = −2"], mode: .ignoreSpaces),

    Case(id: "M13", area: .math, desc: "chemistry with HTML <sub> (web/Docs style)", width: 520,
         css: "#cap{font-family:Georgia;font-size:22px;line-height:1.7} p{margin:0}",
         html: #"<p>2H<sub>2</sub> + O<sub>2</sub> → 2H<sub>2</sub>O</p><p>CO<sub>2</sub> + H<sub>2</sub>O → H<sub>2</sub>CO<sub>3</sub></p>"#,
         expected: ["2H₂ + O₂ → 2H₂O\nCO₂ + H₂O → H₂CO₃"], mode: .ignoreSpaces),

    Case(id: "M14", area: .math, desc: "units with HTML <sup>: m/s², 10⁻³, m s⁻¹", width: 520,
         css: "#cap{font-family:Helvetica;font-size:20px;line-height:1.8} p{margin:0}",
         html: #"<p>g = 9.81 m/s<sup>2</sup></p><p>1 mm = 10<sup>−3</sup> m</p><p>c = 3.00 × 10<sup>8</sup> m s<sup>−1</sup></p>"#,
         expected: ["g = 9.81 m/s²\n1 mm = 10⁻³ m\nc = 3.00 × 10⁸ m s⁻¹"], mode: .ignoreSpaces),

    Case(id: "M15", area: .math, desc: "derivatives: dy/dx (stacked) and f′(x)", fit: true, css: mathCSS,
         html: #"""
         <math display="block"><mfrac><mrow><mi>d</mi><mi>y</mi></mrow><mrow><mi>d</mi><mi>x</mi></mrow></mfrac><mo>=</mo><mn>3</mn><msup><mi>x</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn></math>
         <math display="block"><msup><mi>f</mi><mo>′</mo></msup><mo>(</mo><mi>x</mi><mo>)</mo><mo>=</mo><mn>2</mn><mi>x</mi><mo>+</mo><mn>1</mn></math>
         """#,
         expected: ["dy/dx = 3x² − 4\nf′(x) = 2x + 1"], mode: .ignoreSpaces),

    Case(id: "M16", area: .math, desc: "multi-character exponents: e^(iπ), 2ⁿ⁺¹", fit: true, css: mathCSS,
         html: #"""
         <math display="block"><msup><mi>e</mi><mrow><mi>i</mi><mi>π</mi></mrow></msup><mo>+</mo><mn>1</mn><mo>=</mo><mn>0</mn></math>
         <math display="block"><msup><mn>2</mn><mrow><mi>n</mi><mo>+</mo><mn>1</mn></mrow></msup><mo>−</mo><mn>1</mn></math>
         """#,
         expected: ["e^(iπ) + 1 = 0\n2ⁿ⁺¹ − 1"], mode: .ignoreSpaces),

    Case(id: "M17", area: .math, desc: "trig identity + log base subscript", fit: true, css: mathCSS,
         html: #"""
         <math display="block"><msup><mi>sin</mi><mn>2</mn></msup><mi>θ</mi><mo>+</mo><msup><mi>cos</mi><mn>2</mn></msup><mi>θ</mi><mo>=</mo><mn>1</mn></math>
         <math display="block"><msub><mi>log</mi><mn>2</mn></msub><mn>8</mn><mo>=</mo><mn>3</mn></math>
         """#,
         expected: ["sin²θ + cos²θ = 1\nlog₂ 8 = 3"], mode: .ignoreSpaces),

    Case(id: "M18", area: .math, desc: "worksheet: numbered questions with inline math + inline fractions", width: 620,
         css: "#cap{font-family:'Times New Roman';font-size:18px;line-height:2} ol{margin:0;padding-left:28px}",
         html: #"""
         <ol>
         <li>Solve <math><mn>3</mn><msup><mi>x</mi><mn>2</mn></msup><mo>−</mo><mn>12</mn><mo>=</mo><mn>0</mn></math>.</li>
         <li>Simplify <math><mfrac><mrow><msup><mi>x</mi><mn>2</mn></msup><mo>−</mo><mn>9</mn></mrow><mrow><mi>x</mi><mo>−</mo><mn>3</mn></mrow></mfrac></math>.</li>
         <li>Find <math><mfrac><mrow><mi>d</mi><mi>y</mi></mrow><mrow><mi>d</mi><mi>x</mi></mrow></mfrac></math> when <math><mi>y</mi><mo>=</mo><mi>sin</mi><mo>(</mo><mn>2</mn><mi>x</mi><mo>)</mo></math>.</li>
         </ol>
         """#,
         expected: ["1. Solve 3x² − 12 = 0.\n2. Simplify (x² − 9)/(x − 3).\n3. Find dy/dx when y = sin(2x)."], mode: .ignoreSpaces),

    Case(id: "M19", area: .math, desc: "1x: PDF-like sentence with <sup> exponents (13 px)", density: 1, width: 560,
         css: "#cap{font-family:Helvetica;font-size:13px;line-height:1.5} p{margin:0}",
         html: #"<p>If f(x) = x<sup>3</sup> − 2x, then f′(x) = 3x<sup>2</sup> − 2 and the stationary points satisfy 3x<sup>2</sup> = 2.</p>"#,
         expected: ["If f(x) = x³ − 2x, then f′(x) = 3x² − 2 and the stationary points satisfy 3x² = 2."]),

    Case(id: "M20", area: .math, desc: "limit with x→0 under lim", fit: true, css: mathCSS,
         html: #"<math display="block"><munder><mi>lim</mi><mrow><mi>x</mi><mo>→</mo><mn>0</mn></mrow></munder><mfrac><mrow><mi>sin</mi><mi>x</mi></mrow><mi>x</mi></mfrac><mo>=</mo><mn>1</mn></math>"#,
         expected: ["lim_(x→0) (sin x)/x = 1", "lim(x→0) (sin x)/x = 1", "lim x→0 (sin x)/x = 1"], mode: .ignoreSpaces),

    Case(id: "M21", area: .math, desc: "slide: compound interest A = P(1 + r/n)ⁿᵗ", fit: true, css: "#cap{font-size:40px;padding:30px}",
         html: #"<math display="block"><mi>A</mi><mo>=</mo><mi>P</mi><msup><mrow><mo>(</mo><mn>1</mn><mo>+</mo><mfrac><mi>r</mi><mi>n</mi></mfrac><mo>)</mo></mrow><mrow><mi>n</mi><mi>t</mi></mrow></msup></math>"#,
         expected: ["A = P(1 + r/n)ⁿᵗ"], mode: .ignoreSpaces),

    Case(id: "M22", area: .math, desc: "Google-Docs style: x<sup>2</sup>, x<sub>1</sub> in Arial 15", width: 640,
         css: "#cap{font-family:Arial;font-size:15px;line-height:1.6} p{margin:0}",
         html: #"<p>Solve x<sup>2</sup> − 5x + 6 = 0, giving x<sub>1</sub> = 2 and x<sub>2</sub> = 3.</p>"#,
         expected: ["Solve x² − 5x + 6 = 0, giving x₁ = 2 and x₂ = 3."]),
]

// MARK: - Layout & reading order

let layout: [Case] = [
    Case(id: "Y01", area: .layout, desc: "two-column article; a paragraph flows across the column break", width: 760,
         css: "#cap{font-family:Georgia;font-size:15px;line-height:1.5} h2{font-size:24px;margin:0 0 12px} .cols{column-count:2;column-gap:36px} p{margin:0 0 12px}",
         html: #"""
         <h2>The Water Cycle</h2>
         <div class="cols">
         <p>Water evaporates from oceans, lakes and rivers when it is heated by the Sun. Plants also release water vapour through their leaves in a process called transpiration.</p>
         <p>As the warm, moist air rises it cools, and the vapour condenses into tiny droplets that form clouds. When the droplets combine and grow heavy enough, they fall back to the ground as precipitation.</p>
         <p>Some of this water flows over the surface into rivers, while the rest soaks into the ground and becomes groundwater, eventually returning to the sea.</p>
         </div>
         """#,
         expected: ["""
         The Water Cycle
         Water evaporates from oceans, lakes and rivers when it is heated by the Sun. Plants also release water vapour through their leaves in a process called transpiration.
         As the warm, moist air rises it cools, and the vapour condenses into tiny droplets that form clouds. When the droplets combine and grow heavy enough, they fall back to the ground as precipitation.
         Some of this water flows over the surface into rivers, while the rest soaks into the ground and becomes groundwater, eventually returning to the sea.
         """]),

    Case(id: "Y02", area: .layout, desc: "three-column newsletter (separate articles)", width: 900,
         css: "#cap{font-family:Helvetica;font-size:14px;line-height:1.5;display:flex;gap:30px} #cap>div{flex:1} h3{font-size:18px;margin:0 0 6px} p{margin:0}",
         html: #"""
         <div><h3>Sports Day</h3><p>Sports day will take place on Friday 14 October on the main field. All students should bring water and a hat.</p></div>
         <div><h3>Library News</h3><p>The library has added 200 new books this term, including graphic novels and revision guides for the IB exams.</p></div>
         <div><h3>Lost Property</h3><p>Unclaimed items will be donated at the end of the month. Please check the box outside the gym.</p></div>
         """#,
         expected: ["""
         Sports Day
         Sports day will take place on Friday 14 October on the main field. All students should bring water and a hat.
         Library News
         The library has added 200 new books this term, including graphic novels and revision guides for the IB exams.
         Lost Property
         Unclaimed items will be donated at the end of the month. Please check the box outside the gym.
         """]),

    Case(id: "Y03", area: .layout, desc: "main text + boxed sidebar (key term)", width: 780,
         css: "#cap{display:flex;gap:28px;align-items:flex-start} .main{flex:1;font-family:Georgia;font-size:16px;line-height:1.5} .main h2{font-size:24px;margin:0 0 10px} .main p{margin:0 0 12px} .side{width:220px;background:#eef3f9;border:1px solid #9bb3cf;padding:14px;font-family:Helvetica;font-size:14px;line-height:1.45} .side b{display:block;margin-bottom:6px}",
         html: #"""
         <div class="main"><h2>Scarcity and Choice</h2>
         <p>Because resources are limited, every decision to use them one way means giving up the chance to use them another way. Economists call this trade-off the opportunity cost of the decision.</p>
         <p>For example, a student who spends the evening working a paid shift gives up time that could have been spent revising for an exam.</p></div>
         <div class="side"><b>Key term</b>Opportunity cost is the value of the next best alternative given up when making a choice.</div>
         """#,
         expected: [
             "Scarcity and Choice\nBecause resources are limited, every decision to use them one way means giving up the chance to use them another way. Economists call this trade-off the opportunity cost of the decision.\nFor example, a student who spends the evening working a paid shift gives up time that could have been spent revising for an exam.\nKey term\nOpportunity cost is the value of the next best alternative given up when making a choice.",
             "Key term\nOpportunity cost is the value of the next best alternative given up when making a choice.\nScarcity and Choice\nBecause resources are limited, every decision to use them one way means giving up the chance to use them another way. Economists call this trade-off the opportunity cost of the decision.\nFor example, a student who spends the evening working a paid shift gives up time that could have been spent revising for an exam.",
         ]),

    Case(id: "Y04", area: .layout, desc: "text, figure (no text inside), caption, text", width: 640,
         css: "#cap{font-family:Georgia;font-size:16px;line-height:1.5} p{margin:0 0 12px} .fig{width:420px;height:170px;margin:4px auto 8px;background:#f4f4f4;border:1px solid #ccc} .cap{font-family:Helvetica;font-size:13px;color:#444;text-align:center;margin:0 40px 14px}",
         html: #"""
         <p>Figure 2 shows how the equilibrium price changes when demand increases.</p>
         <div class="fig"><svg width="420" height="170"><line x1="40" y1="150" x2="400" y2="150" stroke="#333" stroke-width="2"/><line x1="40" y1="150" x2="40" y2="10" stroke="#333" stroke-width="2"/><line x1="70" y1="30" x2="330" y2="140" stroke="#c0392b" stroke-width="3"/><line x1="120" y1="30" x2="380" y2="140" stroke="#e67e22" stroke-width="3" stroke-dasharray="8 5"/><line x1="70" y1="140" x2="350" y2="25" stroke="#2c3e50" stroke-width="3"/></svg></div>
         <div class="cap">Figure 2. An increase in demand shifts the demand curve to the right, raising both price and quantity.</div>
         <p>The new equilibrium is found where the new demand curve crosses the supply curve.</p>
         """#,
         expected: ["""
         Figure 2 shows how the equilibrium price changes when demand increases.
         Figure 2. An increase in demand shifts the demand curve to the right, raising both price and quantity.
         The new equilibrium is found where the new demand curve crosses the supply curve.
         """]),

    Case(id: "Y05", area: .layout, desc: "textbook page: running header (left+page no.), body, footer", width: 640,
         css: "#cap{font-family:'Times New Roman';font-size:16px;line-height:1.5} .hd{display:flex;justify-content:space-between;font-size:12px;color:#555;border-bottom:1px solid #999;padding-bottom:4px;margin-bottom:16px} p{margin:0 0 20px;text-align:justify} .ft{text-align:center;font-size:12px;color:#555}",
         html: #"""
         <div class="hd"><span>Chapter 4 · Kinematics</span><span>57</span></div>
         <p>Displacement is a vector quantity: it has both magnitude and direction. The distance travelled, by contrast, is a scalar and is always positive.</p>
         <div class="ft">Physics for the IB Diploma</div>
         """#,
         expected: tabOrSpace("Chapter 4 · Kinematics\t57\nDisplacement is a vector quantity: it has both magnitude and direction. The distance travelled, by contrast, is a scalar and is always positive.\nPhysics for the IB Diploma")),

    Case(id: "Y06", area: .layout, desc: "UI settings form: right-aligned labels + field values + buttons", width: 520,
         css: "#cap{font-family:-apple-system,'SF Pro Text',Helvetica;font-size:13px;background:#ececec;padding:22px} .row{display:flex;align-items:center;margin:8px 0} .l{width:130px;text-align:right;padding-right:10px} .f{background:#fff;border:1px solid #bdbdbd;border-radius:4px;padding:4px 8px;width:220px} .cb{display:inline-block;width:13px;height:13px;background:#2f7cf6;border-radius:3px;margin-right:6px;vertical-align:-2px} .btns{display:flex;justify-content:flex-end;gap:10px;margin-top:18px} .b{background:#fff;border:1px solid #bdbdbd;border-radius:5px;padding:3px 16px} .b.p{background:#2f7cf6;color:#fff;border-color:#2f7cf6}",
         html: #"""
         <div class="row"><div class="l">Display name:</div><div class="f">David Popescu</div></div>
         <div class="row"><div class="l">Email:</div><div class="f">david@example.com</div></div>
         <div class="row"><div class="l">Theme:</div><div class="f" style="width:90px">Dark</div></div>
         <div class="row"><div class="l"></div><div><span class="cb"></span>Start at login</div></div>
         <div class="btns"><div class="b">Cancel</div><div class="b p">Save</div></div>
         """#,
         expected: tabOrSpace("Display name:\tDavid Popescu\nEmail:\tdavid@example.com\nTheme:\tDark\nStart at login\nCancel\tSave")),

    Case(id: "Y07", area: .layout, desc: "slide: title + two bullet columns", width: 960,
         css: "#cap{font-family:'Helvetica Neue';padding:40px 56px} h1{font-size:40px;margin:0 0 24px} .cols{display:flex;gap:60px} .cols>div{flex:1} h3{font-size:28px;margin:0 0 10px} ul{font-size:24px;line-height:1.5;margin:0;padding-left:30px}",
         html: #"""
         <h1>Nuclear Power</h1>
         <div class="cols"><div><h3>Advantages</h3><ul><li>Low carbon emissions</li><li>Reliable baseload supply</li><li>High energy density</li></ul></div>
         <div><h3>Disadvantages</h3><ul><li>Radioactive waste</li><li>High construction cost</li><li>Risk of accidents</li></ul></div></div>
         """#,
         expected: ["""
         Nuclear Power
         Advantages
         • Low carbon emissions
         • Reliable baseload supply
         • High energy density
         Disadvantages
         • Radioactive waste
         • High construction cost
         • Risk of accidents
         """]),

    Case(id: "Y08", area: .layout, desc: "chat screenshot: left/right bubbles + timestamp", width: 440,
         css: "#cap{font-family:-apple-system,Helvetica;font-size:15px;line-height:1.35;display:flex;flex-direction:column;gap:8px} .ts{text-align:center;font-size:11px;color:#888} .m{max-width:250px;padding:8px 12px;border-radius:17px} .in{background:#e9e9eb;align-self:flex-start} .out{background:#0b84ff;color:#fff;align-self:flex-end}",
         html: #"""
         <div class="ts">Today 16:42</div>
         <div class="m in">Hey, are we still meeting at 5 to work on the chemistry lab write-up?</div>
         <div class="m out">Yes! At the library, second floor.</div>
         <div class="m in">Great, I'll bring the notes.</div>
         <div class="m out">Perfect, see you there</div>
         """#,
         expected: ["""
         Today 16:42
         Hey, are we still meeting at 5 to work on the chemistry lab write-up?
         Yes! At the library, second floor.
         Great, I'll bring the notes.
         Perfect, see you there
         """]),
]

// MARK: - Robustness

let robustness: [Case] = [
    Case(id: "R01", area: .robustness, desc: "dark mode: light text on #1e1e1e", width: 620,
         css: "#cap{background:#1e1e1e;color:#e6e6e6;font-family:-apple-system,Helvetica;font-size:15px;line-height:1.5} p{margin:0 0 10px}",
         html: #"""
         <p>Reminder: the extended essay first draft is due on Monday. Upload it to ManageBac as a PDF and include your word count on the title page.</p>
         <p>Late submissions will not receive written feedback.</p>
         """#,
         expected: ["Reminder: the extended essay first draft is due on Monday. Upload it to ManageBac as a PDF and include your word count on the title page.\nLate submissions will not receive written feedback."]),

    Case(id: "R02", area: .robustness, desc: "1x: 10 px footnote", density: 1, width: 460,
         css: "#cap{font-family:Helvetica;font-size:10px;line-height:1.4;padding:12px} p{margin:0}",
         html: #"<p>Data from the National Institute of Statistics, 2023 edition. Figures are rounded to the nearest thousand and exclude temporary residents.</p>"#,
         expected: ["Data from the National Institute of Statistics, 2023 edition. Figures are rounded to the nearest thousand and exclude temporary residents."]),

    Case(id: "R03", area: .robustness, desc: "white text on a blue-purple gradient banner", width: 760,
         css: "#cap{background:linear-gradient(120deg,#1e3c72,#7b2ff7 60%,#f107a3);color:#fff;font-family:'Helvetica Neue';padding:40px} .h{font-size:42px;font-weight:700} .s{font-size:22px;margin-top:10px;opacity:.9}",
         html: #"<div class="h">Science Fair 2025</div><div class="s">Friday 21 March · Main Hall · 14:00–17:00</div>"#,
         expected: ["Science Fair 2025\nFriday 21 March · Main Hall · 14:00–17:00"]),

    Case(id: "R04", area: .robustness, desc: "coloured backgrounds + low-contrast grey text", width: 560,
         css: "#cap{font-family:Helvetica;font-size:17px;padding:0} div.x{padding:12px 20px}",
         html: #"""
         <div class="x" style="background:#ffe066;color:#c0392b">Warning: this solution is corrosive.</div>
         <div class="x" style="background:#d5f5e3;color:#1e8449">Safe to handle with gloves.</div>
         <div class="x" style="background:#fff;color:#aaa">Optional: wear safety glasses.</div>
         """#,
         expected: ["Warning: this solution is corrosive.\nSafe to handle with gloves.\nOptional: wear safety glasses."]),

    Case(id: "R05", area: .robustness, desc: "Romanian diacritics (ș ț with comma below, ă â î)", width: 720,
         css: "#cap{font-family:Georgia;font-size:19px;line-height:1.6} p{margin:0 0 8px}",
         html: #"""
         <p>În școală, elevii își țin caietele în bănci și ascultă lecția de fizică.</p>
         <p>Mâine vom învăța despre câmpul electric și despre sarcinile electrice.</p>
         """#,
         expected: ["În școală, elevii își țin caietele în bănci și ascultă lecția de fizică.\nMâine vom învăța despre câmpul electric și despre sarcinile electrice."]),

    Case(id: "R06", area: .robustness, desc: "German / French / Spanish accents", width: 760,
         css: "#cap{font-family:Georgia;font-size:19px;line-height:1.6} p{margin:0 0 8px}",
         html: #"<p>Der Bär läuft über die Brücke.</p><p>Le garçon a mangé une crème brûlée.</p><p>El niño tiene cinco años.</p>"#,
         expected: ["Der Bär läuft über die Brücke.\nLe garçon a mangé une crème brûlée.\nEl niño tiene cinco años."]),

    Case(id: "R07", area: .robustness, desc: "QR code alone", fit: true,
         html: #"<img src="{{QR:https://www.ibo.org/programmes/diploma-programme/}}" width="200" height="200" style="image-rendering:pixelated;display:block">"#,
         expected: ["https://www.ibo.org/programmes/diploma-programme/"]),

    Case(id: "R08", area: .robustness, desc: "poster text + small QR in the corner", width: 620,
         css: "#cap{font-family:'Helvetica Neue';position:relative;padding:30px 150px 30px 30px;background:#fdf6e3} h2{font-size:30px;margin:0 0 10px} p{font-size:17px;line-height:1.5;margin:0} img{position:absolute;right:24px;bottom:24px;image-rendering:pixelated}",
         html: #"""
         <h2>Join the Robotics Club</h2>
         <p>Meetings every Thursday at 15:30 in room B12. Everyone is welcome, no experience needed.</p>
         <img src="{{QR:https://forms.example.com/robotics}}" width="84" height="84">
         """#,
         expected: [
             "Join the Robotics Club\nMeetings every Thursday at 15:30 in room B12. Everyone is welcome, no experience needed.",
             "Join the Robotics Club\nMeetings every Thursday at 15:30 in room B12. Everyone is welcome, no experience needed.\nhttps://forms.example.com/robotics",
         ]),

    Case(id: "R09", area: .robustness, desc: "no text: gradient + shapes", width: 500,
         css: "#cap{height:260px;background:radial-gradient(circle at 30% 40%,#ffd194,#70e1f5 60%,#3a6186);position:relative} .c{position:absolute;border-radius:50%;background:rgba(255,255,255,.5)}",
         html: #"<div class="c" style="left:60px;top:50px;width:90px;height:90px"></div><div class="c" style="left:300px;top:120px;width:60px;height:60px"></div>"#,
         expected: []),
]
