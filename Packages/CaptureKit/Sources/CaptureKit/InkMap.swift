import CoreGraphics

/// A binarized crop of an image: which pixels are ink (text), with the
/// connected blobs of ink. Top-left origin, pixel units. Works for dark text on
/// light and light text on dark: the background is whatever dominates the
/// crop's border.
struct InkMap {
    let width: Int
    let height: Int
    /// Row-major, true = ink.
    let ink: [Bool]

    struct Blob {
        var box: CGRect
        var pixels: [Int]
    }

    init(width: Int, height: Int, ink: [Bool]) {
        self.width = width
        self.height = height
        self.ink = ink
    }

    /// Renders `rect` (top-left pixel coordinates in `image`) to grey and
    /// thresholds it with Otsu's method.
    init?(_ image: CGImage, rect: CGRect) {
        let crop = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let w = Int(crop.width), h = Int(crop.height)
        guard w > 2, h > 2, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                                 space: CGColorSpaceCreateDeviceGray(),
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Memory row 0 is the top row; CG draws with a bottom-left origin.
        ctx.draw(image, in: CGRect(x: -crop.minX, y: -(CGFloat(image.height) - crop.maxY),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let data = ctx.data else { return nil }
        let gray = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h))
        let t = InkMap.otsu(gray)
        var borderDark = 0, border = 0
        for x in 0..<w { for y in [0, h - 1] { border += 1; if gray[y * w + x] < t { borderDark += 1 } } }
        for y in 0..<h { for x in [0, w - 1] { border += 1; if gray[y * w + x] < t { borderDark += 1 } } }
        let lightBackground = borderDark * 2 < border
        self.init(width: w, height: h, ink: gray.map { lightBackground ? $0 < t : $0 >= t })
    }

    static func otsu(_ gray: [UInt8]) -> UInt8 {
        var histogram = [Int](repeating: 0, count: 256)
        for g in gray { histogram[Int(g)] += 1 }
        let total = Double(gray.count)
        let sum = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
        var sumB = 0.0, weightB = 0.0, best = 0.0, threshold = 128
        for t in 0..<256 {
            weightB += Double(histogram[t])
            guard weightB > 0 else { continue }
            let weightF = total - weightB
            guard weightF > 0 else { break }
            sumB += Double(t * histogram[t])
            let meanB = sumB / weightB, meanF = (sum - sumB) / weightF
            let between = weightB * weightF * (meanB - meanF) * (meanB - meanF)
            if between > best { best = between; threshold = t }
        }
        return UInt8(min(threshold + 1, 255))
    }

    /// The longest horizontal run of ink on any row, in pixels.
    func longestRun() -> CGFloat {
        var best = 0
        for y in 0..<height {
            var run = 0
            for x in 0..<width {
                if ink[y * width + x] { run += 1; best = max(best, run) } else { run = 0 }
            }
        }
        return CGFloat(best)
    }

    /// 8-connected blobs of ink, left to right.
    func blobs() -> [Blob] {
        var label = [Int32](repeating: -1, count: width * height)
        var blobs: [Blob] = []
        var stack: [Int] = []
        for start in 0..<(width * height) where ink[start] && label[start] < 0 {
            let id = Int32(blobs.count)
            var pixels: [Int] = []
            var minX = width, minY = height, maxX = 0, maxY = 0
            label[start] = id
            stack.append(start)
            while let p = stack.popLast() {
                pixels.append(p)
                let x = p % width, y = p / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let q = ny * width + nx
                        if ink[q] && label[q] < 0 { label[q] = id; stack.append(q) }
                    }
                }
            }
            blobs.append(Blob(box: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
                              pixels: pixels))
        }
        return blobs.sorted { $0.box.minX < $1.box.minX }
    }
}
