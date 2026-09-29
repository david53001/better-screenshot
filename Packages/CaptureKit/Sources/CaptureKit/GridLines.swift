import CoreGraphics

/// A table's vertical grid lines, from the pixels: a thin stripe darker (or,
/// on a dark theme, lighter) than the pixels a few columns to either side,
/// unbroken down a row. Compared locally rather than binarized — a
/// spreadsheet's faint #e2e2e2 lines fall below any threshold tuned for text
/// (InkMap's Otsu), and zebra or header shading changes the background per row.
struct GridLines {
    let width: Int
    let height: Int
    /// Row-major grey levels, top row first.
    let gray: [UInt8]

    /// Pixels either side a line is compared with: a 1–4 px line (a 1 pt rule
    /// at 2×, or a 1 px one upscaled from 1×) is narrower than twice this.
    static let side = 3
    /// Grey levels a line must differ from both sides by.
    static let contrast = 8
    /// Share of the rows a line must cross (anti-aliasing may nick one).
    static let coverage = 0.9

    init(width: Int, height: Int, gray: [UInt8]) {
        self.width = width
        self.height = height
        self.gray = gray
    }

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 2 * GridLines.side, h > 2,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        self.init(width: w, height: h, gray: Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h)))
    }

    /// x positions (pixel centres) of the vertical lines crossing all of
    /// `rect` (top-left pixel coordinates).
    func vertical(in rect: CGRect) -> [CGFloat] {
        let side = GridLines.side, contrast = GridLines.contrast
        let y0 = max(0, Int(rect.minY.rounded(.down))), y1 = min(height, Int(rect.maxY.rounded(.up)))
        let x0 = max(side, Int(rect.minX.rounded(.down))), x1 = min(width - side, Int(rect.maxX.rounded(.up)))
        guard y1 - y0 >= 3, x1 > x0 else { return [] }
        var hits = [Int](repeating: 0, count: x1 - x0)
        for y in y0..<y1 {
            let row = y * width
            for x in x0..<x1 {
                let c = Int(gray[row + x]), l = Int(gray[row + x - side]), r = Int(gray[row + x + side])
                if (l - c >= contrast && r - c >= contrast) || (c - l >= contrast && c - r >= contrast) { hits[x - x0] += 1 }
            }
        }
        let need = Int((GridLines.coverage * Double(y1 - y0)).rounded(.up))
        var lines: [CGFloat] = []
        var start: Int?
        for dx in 0...hits.count {
            if dx < hits.count, hits[dx] >= need {
                if start == nil { start = dx }
            } else if let s = start {
                lines.append(CGFloat(x0) + CGFloat(s + dx) / 2)
                start = nil
            }
        }
        return lines
    }
}
