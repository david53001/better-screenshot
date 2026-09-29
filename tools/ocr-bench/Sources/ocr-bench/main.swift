import AppKit
import CaptureKit

// ocr-bench — Capture Text corpus runner. See README.md.
setvbuf(stdout, nil, _IONBF, 0)

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i); return true
}

// Run from the package root; results go to ./out unless --out is given.
let outDir = URL(fileURLWithPath: option("--out") ?? FileManager.default.currentDirectoryPath + "/out")
let only = option("--only").map { Set($0.split(separator: ",").map(String.init)) }
let areaFilter = option("--area").flatMap(Area.init(rawValue:))
let forcedDensity = option("--density").flatMap(Int.init)
let withLiveText = flag("--livetext")
let withRaw = flag("--rawvision")
/// `--no-math`: run Capture Text with Settings → Recognize math off.
let recognizeMath = !flag("--no-math")
let rerender = flag("--render")
let command = args.first ?? "all"

let suffix = forcedDensity.map { "-forced-\($0)x" } ?? ""
let imageDir = outDir.appendingPathComponent("images" + suffix)
try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)

var selected = cases.filter { c in
    (only == nil || only!.contains(c.id)) && (areaFilter == nil || c.area == areaFilter)
}
if command == "dump" { selected = cases.filter { args.dropFirst().contains($0.id) } }
if let d = forcedDensity { selected = selected.map { var c = $0; c.density = d; return c } }

if command == "probes" { runProbes(); exit(0) }

if command == "list" {
    for c in cases { print("\(c.id)\t\(c.area.rawValue)\t\(c.density)x\t\(c.desc)") }
    exit(0)
}

// MARK: render

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()

func imageURL(_ c: Case) -> URL { imageDir.appendingPathComponent("\(c.id).png") }

func render(_ c: Case, with renderer: Renderer) throws -> CGImage {
    let doc = expandQRPlaceholders(c.document)
    let full = try renderer.render(document: doc, widthPt: c.width)   // 2x (window backing scale)
    let scale = Int(renderer.backingScale.rounded())
    let image = c.density < scale ? (downscale(full, by: scale / c.density) ?? full) : full
    writePNG(image, to: imageURL(c))
    return image
}

var images: [String: CGImage] = [:]
do {
    let renderer = Renderer()
    renderer.debug = false
    guard renderer.backingScale == 2 else {
        print("error: offscreen window backing scale is \(renderer.backingScale), expected 2"); exit(2)
    }
    for c in selected {
        if !rerender, command != "render", let img = loadPNG(imageURL(c)) { images[c.id] = img; continue }
        do { images[c.id] = try render(c, with: renderer) }
        catch { print("render failed \(c.id): \(error)") }
    }
    renderer.close()
}
if command == "render" { print("rendered \(images.count) images → \(imageDir.path)"); exit(0) }

// MARK: dump

if command == "dump" {
    for c in selected {
        guard let img = images[c.id] else { continue }
        print("=== \(c.id) \(c.desc)")
        dumpVision(img, density: c.density)
        let r = try? TextRecognizer.recognize(in: img, pointWidth: CGFloat(img.width) / CGFloat(c.density), math: recognizeMath)
        print("  clipboard: \(r?.clipboardString?.debugDescription ?? "nil")")
    }
    exit(0)
}

// MARK: run

struct Row: Codable {
    var id, area, desc: String
    var density: Int
    var pass: Bool
    var cer, glyphCER: Double
    var expected: String
    var actual: String?
    var liveText: String?
    var livePass: Bool?
    var liveCER: Double?
    var raw: String?
    var rawPass: Bool?
    var rawCER: Double?
    var ms: Int
}

var rows: [Row] = []
var report = ""
for c in selected {
    guard let img = images[c.id] else { continue }
    let t0 = Date()
    let result = try? TextRecognizer.recognize(in: img, pointWidth: CGFloat(img.width) / CGFloat(c.density), math: recognizeMath)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    let actual = result?.clipboardString
    let s = score(c, actual: actual)
    var row = Row(id: c.id, area: c.area.rawValue, desc: c.desc, density: c.density, pass: s.pass,
                  cer: s.cer, glyphCER: s.glyphCER, expected: c.expected.first ?? "", actual: actual, ms: ms)
    if withLiveText {
        let live = liveTextTranscript(img)
        let ls = score(c, actual: live)
        row.liveText = live; row.livePass = ls.pass; row.liveCER = ls.cer
    }
    if withRaw {
        let raw = rawVisionText(img, density: c.density)
        let rs = score(c, actual: raw)
        row.raw = raw; row.rawPass = rs.pass; row.rawCER = rs.cer
    }
    rows.append(row)
    var block = String(format: "[%@] %@ %@ %dx — %@  (CER %.2f, glyph CER %.2f, %d ms)\n",
                       s.pass ? "PASS" : "FAIL", c.id, c.area.rawValue, c.density, c.desc, s.cer, s.glyphCER, ms)
    block += "  expected:\n\(visible(c.expected.first))\n  actual:\n\(visible(actual))\n"
    if withLiveText {
        block += String(format: "  live text (%@, CER %.2f):\n", row.livePass! ? "PASS" : "FAIL", row.liveCER!)
        block += visible(row.liveText) + "\n"
    }
    if withRaw {
        block += String(format: "  raw Vision order, no reflow (%@, CER %.2f):\n", row.rawPass! ? "PASS" : "FAIL", row.rawCER!)
        block += visible(row.raw) + "\n"
    }
    print(block)
    report += block + "\n"
}

// MARK: summary

var summary = "| Area | Cases | Pass | Mean CER | Mean glyph CER |" + (withLiveText ? " Live Text pass | Live Text CER |" : "") + (withRaw ? " Raw Vision pass | Raw Vision CER |" : "") + "\n"
summary += "|---|---|---|---|---|" + (withLiveText ? "---|---|" : "") + (withRaw ? "---|---|" : "") + "\n"
func line(_ name: String, _ rs: [Row]) -> String {
    guard !rs.isEmpty else { return "" }
    let n = Double(rs.count)
    var l = String(format: "| %@ | %d | %d/%d | %.2f | %.2f |", name, rs.count, rs.filter(\.pass).count, rs.count,
                   rs.map(\.cer).reduce(0, +) / n, rs.map(\.glyphCER).reduce(0, +) / n)
    if withLiveText {
        l += String(format: " %d/%d | %.2f |", rs.filter { $0.livePass == true }.count, rs.count,
                    rs.compactMap(\.liveCER).reduce(0, +) / n)
    }
    if withRaw {
        l += String(format: " %d/%d | %.2f |", rs.filter { $0.rawPass == true }.count, rs.count,
                    rs.compactMap(\.rawCER).reduce(0, +) / n)
    }
    return l + "\n"
}
for a in Area.allCases { summary += line(a.rawValue, rows.filter { $0.area == a.rawValue }) }
summary += line("**all**", rows)
print(summary)

let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try? enc.encode(rows).write(to: outDir.appendingPathComponent("results\(suffix).json"))
try? report.write(to: outDir.appendingPathComponent("results\(suffix).txt"), atomically: true, encoding: .utf8)
try? summary.write(to: outDir.appendingPathComponent("summary\(suffix).md"), atomically: true, encoding: .utf8)
print("wrote \(outDir.path)/results\(suffix).{txt,json}, summary\(suffix).md")
exit(0)
