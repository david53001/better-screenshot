// Table cases for the "cell lands in the wrong column" fix (review 2026-09-29,
// issues T1/T2). Written with their ground truth before any output was seen:
// gridded sheets with narrow columns and empty cells, bordered tables with
// merged (spanning) cells, and gridless tables that must not regress.
// Convention (same as V30): a merged cell goes in the first column it spans,
// like a spreadsheet's merged range; trailing empty cells may be dropped.

let gridCases: [Case] = [
    Case(id: "G01", area: .tables, desc: "1x gridded parts sheet (Helvetica 13): narrow Qty/Bin columns, empty cells mid-row", density: 1, width: 640,
         css: "#cap{font-family:Helvetica;font-size:13px;padding:10px;background:#fff} table{border-collapse:collapse} td{border:1px solid #dadce0;padding:3px 6px;white-space:nowrap;height:18px} td.r{text-align:right} tr.h td{font-weight:bold;background:#f1f3f4}",
         html: #"""
         <table><tr class="h"><td>Item</td><td>Qty</td><td>Bin</td><td>Unit price</td><td>Supplier</td></tr>
         <tr><td>Resistor 10k</td><td class="r">250</td><td>A2</td><td class="r">0.02</td><td>Farnell</td></tr>
         <tr><td>Capacitor 10nF</td><td class="r"></td><td>B1</td><td class="r">0.05</td><td></td></tr>
         <tr><td>LED red</td><td class="r">40</td><td>C7</td><td class="r"></td><td>Mouser</td></tr>
         <tr><td>Header 2x5</td><td class="r">12</td><td></td><td class="r">0.30</td><td>Farnell</td></tr></table>
         """#,
         expected: ["Item\tQty\tBin\tUnit price\tSupplier\nResistor 10k\t250\tA2\t0.02\tFarnell\nCapacitor 10nF\t\tB1\t0.05\nLED red\t40\tC7\t\tMouser\nHeader 2x5\t12\t\t0.30\tFarnell"]),

    Case(id: "G02", area: .tables, desc: "bordered gradebook (Georgia 14): header cells merged across two columns each", width: 620,
         css: "#cap{font-family:Georgia;font-size:14px} table{border-collapse:collapse} td,th{border:1px solid #777;padding:5px 12px;white-space:nowrap;text-align:center} th{background:#eee} td.l,th.l{text-align:left}",
         html: #"""
         <table><tr><th class="l">Subject</th><th colspan="2">Term 1</th><th colspan="2">Term 2</th></tr>
         <tr><th></th><th>Test</th><th>Homework</th><th>Test</th><th>Homework</th></tr>
         <tr><td class="l">Biology</td><td>68</td><td>74</td><td>71</td><td>80</td></tr>
         <tr><td class="l">Chemistry</td><td>59</td><td>66</td><td>63</td><td>70</td></tr>
         <tr><td class="l">History</td><td>82</td><td>77</td><td>85</td><td>79</td></tr></table>
         """#,
         expected: ["Subject\tTerm 1\t\tTerm 2\n\tTest\tHomework\tTest\tHomework\nBiology\t68\t74\t71\t80\nChemistry\t59\t66\t63\t70\nHistory\t82\t77\t85\t79"]),

    Case(id: "G03", area: .tables, desc: "gridless medal table (Helvetica Neue 14): narrow 2-letter code column, right-aligned numbers", width: 600,
         css: "#cap{font-family:'Helvetica Neue';font-size:14px} table{border-collapse:collapse} td{padding:4px 10px;white-space:nowrap} td.r{text-align:right} tr.h td{font-weight:bold;border-bottom:1px solid #999}",
         html: #"""
         <table><tr class="h"><td>Country</td><td>Code</td><td class="r">Gold</td><td class="r">Silver</td><td class="r">Bronze</td><td class="r">Total</td></tr>
         <tr><td>Norway</td><td>NO</td><td class="r">16</td><td class="r">8</td><td class="r">13</td><td class="r">37</td></tr>
         <tr><td>Germany</td><td>DE</td><td class="r">12</td><td class="r">10</td><td class="r">5</td><td class="r">27</td></tr>
         <tr><td>Canada</td><td>CA</td><td class="r">11</td><td class="r">8</td><td class="r">10</td><td class="r">29</td></tr>
         <tr><td>United States</td><td>US</td><td class="r">9</td><td class="r">8</td><td class="r">8</td><td class="r">25</td></tr></table>
         """#,
         expected: ["Country\tCode\tGold\tSilver\tBronze\tTotal\nNorway\tNO\t16\t8\t13\t37\nGermany\tDE\t12\t10\t5\t27\nCanada\tCA\t11\t8\t10\t29\nUnited States\tUS\t9\t8\t8\t25"]),

    Case(id: "G04", area: .tables, desc: "dark-mode gridded task sheet (SF 13): narrow Est column, empty cells in several columns", width: 560,
         css: "#cap{background:#1e1e1e;color:#d4d4d4;font-family:-apple-system,Helvetica;font-size:13px;padding:12px} table{border-collapse:collapse} td{border:1px solid #3c3c3c;padding:4px 8px;white-space:nowrap} tr.h td{font-weight:600;background:#262626}",
         html: #"""
         <table><tr class="h"><td>Task</td><td>Owner</td><td>Est</td><td>Status</td></tr>
         <tr><td>Login page</td><td>Ana</td><td>3d</td><td>Done</td></tr>
         <tr><td>API tokens</td><td>Radu</td><td></td><td>Blocked</td></tr>
         <tr><td>Search</td><td>Ioana</td><td>5d</td><td></td></tr>
         <tr><td>Export CSV</td><td></td><td>2d</td><td>Todo</td></tr></table>
         """#,
         expected: ["Task\tOwner\tEst\tStatus\nLogin page\tAna\t3d\tDone\nAPI tokens\tRadu\t\tBlocked\nSearch\tIoana\t5d\nExport CSV\t\t2d\tTodo"]),

    Case(id: "G05", area: .tables, desc: "bordered weekly plan (Avenir 14): a centred body cell merged across three columns", width: 660,
         css: "#cap{font-family:Avenir;font-size:14px} table{border-collapse:collapse} td,th{border:1px solid #9aa3b2;padding:6px 12px;white-space:nowrap;text-align:left} th{background:#e8edf5} td.m{text-align:center;background:#fafafa}",
         html: #"""
         <table><tr><th>Day</th><th>09:00</th><th>10:00</th><th>11:00</th><th>12:00</th></tr>
         <tr><td>Monday</td><td>Chemistry</td><td>Chemistry</td><td>Art</td><td>Music</td></tr>
         <tr><td>Tuesday</td><td class="m" colspan="3">Field trip</td><td>Drama</td></tr>
         <tr><td>Wednesday</td><td>Maths</td><td>Free</td><td>Biology</td><td>Art</td></tr></table>
         """#,
         expected: ["Day\t09:00\t10:00\t11:00\t12:00\nMonday\tChemistry\tChemistry\tArt\tMusic\nTuesday\tField trip\t\t\tDrama\nWednesday\tMaths\tFree\tBiology\tArt"]),

    Case(id: "G06", area: .tables, desc: "1x gridded budget sheet (Arial 12): narrow % column right after a number, empty cells", density: 1, width: 560,
         css: "#cap{font-family:Arial;font-size:12px;padding:8px;background:#fff} table{border-collapse:collapse} td{border:1px solid #e0e0e0;padding:2px 5px;white-space:nowrap;height:17px} td.r{text-align:right} tr.h td{font-weight:bold}",
         html: #"""
         <table><tr class="h"><td>Category</td><td>Budget</td><td>%</td><td>Spent</td><td>Left</td></tr>
         <tr><td>Rent</td><td class="r">1200</td><td class="r">48</td><td class="r">1200</td><td class="r">0</td></tr>
         <tr><td>Food</td><td class="r">450</td><td class="r">18</td><td class="r"></td><td class="r">450</td></tr>
         <tr><td>Transport</td><td class="r">120</td><td class="r"></td><td class="r">95</td><td class="r">25</td></tr>
         <tr><td>Savings</td><td class="r">300</td><td class="r">12</td><td class="r">300</td><td class="r"></td></tr></table>
         """#,
         expected: ["Category\tBudget\t%\tSpent\tLeft\nRent\t1200\t48\t1200\t0\nFood\t450\t18\t\t450\nTransport\t120\t\t95\t25\nSavings\t300\t12\t300"]),
]
