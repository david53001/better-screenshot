import AppKit
// usage: evidence out.jpg id1 id2 ...  (reads out/results.json + images)
struct Row: Decodable { var id: String; var desc: String; var expected: String; var actual: String?; var liveText: String?; var cer: Double }
let a = CommandLine.arguments
let rows = try! JSONDecoder().decode([Row].self, from: Data(contentsOf: URL(fileURLWithPath: "out/results.json")))
let W: CGFloat = 1200, pad: CGFloat = 16
let mono = NSFont(name: "Menlo", size: 15)!, bold = NSFont.boldSystemFont(ofSize: 17), lab = NSFont.boldSystemFont(ofSize: 13)
func vis(_ s: String?) -> String { (s ?? "<no text found — clipboard untouched>").replacingOccurrences(of: "\t", with: " ⇥ ") }
func textHeight(_ s: String, _ f: NSFont, _ w: CGFloat) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: f]).boundingRect(with: NSSize(width: w, height: 10000), options: [.usesLineFragmentOrigin]).height + 4 }
struct Block { var kind: Int; var text: String; var image: CGImage?; var h: CGFloat; var color: NSColor }
var blocks: [Block] = []
for id in a.dropFirst(2) {
    guard let r = rows.first(where: { $0.id == id }) else { continue }
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "out/images/\(id).png") as CFURL, nil)!
    let im = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let title = "\(id) — \(r.desc)   (CER \(String(format: "%.2f", r.cer)))"
    blocks.append(Block(kind: 0, text: title, image: nil, h: textHeight(title, bold, W - 2*pad) + 6, color: .black))
    let maxW = W - 2*pad, s = min(1, maxW / CGFloat(im.width), 380 / CGFloat(im.height))
    blocks.append(Block(kind: 1, text: "", image: im, h: CGFloat(im.height) * s + 8, color: .black))
    for (label, text, color) in [("Expected (what a careful human types)", r.expected, NSColor(calibratedRed: 0, green: 0.45, blue: 0.1, alpha: 1)),
                                 ("Clipboard — BetterScreenshot Capture Text", vis(r.actual), NSColor(calibratedRed: 0.75, green: 0, blue: 0, alpha: 1))] + (r.liveText != nil || true ? [("macOS Live Text (same image, for comparison)", vis(r.liveText), NSColor.darkGray)] : []) {
        let t = text.replacingOccurrences(of: "\t", with: " ⇥ ")
        blocks.append(Block(kind: 2, text: label, image: nil, h: 20, color: color))
        blocks.append(Block(kind: 3, text: t, image: nil, h: textHeight(t, mono, W - 2*pad - 12) + 10, color: color))
    }
    blocks.append(Block(kind: 4, text: "", image: nil, h: 22, color: .black))
}
let H = blocks.reduce(pad) { $0 + $1.h }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
var y = H - pad
for b in blocks {
    y -= b.h
    switch b.kind {
    case 0: (b.text as NSString).draw(with: NSRect(x: pad, y: y, width: W - 2*pad, height: b.h), options: [.usesLineFragmentOrigin], attributes: [.font: bold])
    case 1:
        let im = b.image!; let s = (b.h - 8) / CGFloat(im.height)
        let r = NSRect(x: pad, y: y + 4, width: CGFloat(im.width) * s, height: b.h - 8)
        NSColor(white: 0.6, alpha: 1).setStroke(); NSBezierPath(rect: r.insetBy(dx: -1, dy: -1)).stroke()
        ctx.cgContext.interpolationQuality = .high; ctx.cgContext.draw(im, in: r)
    case 2: (b.text as NSString).draw(at: NSPoint(x: pad, y: y + 2), withAttributes: [.font: lab, .foregroundColor: b.color])
    case 3:
        NSColor(white: 0.95, alpha: 1).setFill(); NSRect(x: pad, y: y + 2, width: W - 2*pad, height: b.h - 4).fill()
        (b.text as NSString).draw(with: NSRect(x: pad + 6, y: y + 4, width: W - 2*pad - 12, height: b.h - 6), options: [.usesLineFragmentOrigin], attributes: [.font: mono, .foregroundColor: b.color])
    default:
        NSColor(white: 0.8, alpha: 1).setFill(); NSRect(x: 0, y: y + 10, width: W, height: 2).fill()
    }
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])!.write(to: URL(fileURLWithPath: a[1]))
