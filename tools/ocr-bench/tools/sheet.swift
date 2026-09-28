import AppKit
// usage: sheet out.png maxWidth img1 img2 ...  — stacks images vertically with labels
let a = CommandLine.arguments
let out = a[1]; let maxW = CGFloat(Double(a[2])!)
var imgs: [(String, CGImage)] = []
for p in a.dropFirst(3) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
          let im = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    imgs.append(((p as NSString).lastPathComponent, im))
}
let label: CGFloat = 26
var sizes = imgs.map { (_, im) -> CGSize in
    let s = min(1, maxW / CGFloat(im.width)); return CGSize(width: CGFloat(im.width) * s, height: CGFloat(im.height) * s) }
let W = Int(maxW), H = Int(sizes.reduce(0) { $0 + $1.height + label + 8 })
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
var y = CGFloat(H)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
for (i, (name, im)) in imgs.enumerated() {
    y -= label
    (name as NSString).draw(at: CGPoint(x: 4, y: y + 4), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.red])
    y -= sizes[i].height
    ctx.interpolationQuality = .high
    ctx.draw(im, in: CGRect(x: 0, y: y, width: sizes[i].width, height: sizes[i].height))
    y -= 8
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
