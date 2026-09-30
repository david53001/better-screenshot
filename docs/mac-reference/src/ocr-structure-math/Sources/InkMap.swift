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

    /// The enclosed holes of a shape made of `pixels` (indices into this map)
    /// inside `box`: background regions the ink walls off from the box's edge
    /// (`o` has one, `θ` and `8` two). Specks under 2% of the box are noise.
    func holes(of pixels: [Int], in box: CGRect) -> [CGRect] {
        let x0 = Int(box.minX), y0 = Int(box.minY), w = Int(box.width), h = Int(box.height)
        guard w > 2, h > 2 else { return [] }
        var cell = [Int8](repeating: 0, count: w * h) // 0 background, 1 ink, 2 reached
        for p in pixels {
            let x = p % width - x0, y = p / width - y0
            if x >= 0, x < w, y >= 0, y < h { cell[y * w + x] = 1 }
        }
        func fill(_ start: Int, mark: Int8) -> [Int] {
            var region: [Int] = [], stack = [start]
            cell[start] = mark
            while let q = stack.popLast() {
                region.append(q)
                let x = q % w, y = q / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where nx >= 0 && nx < w && ny >= 0 && ny < h && cell[ny * w + nx] == 0 {
                    cell[ny * w + nx] = mark
                    stack.append(ny * w + nx)
                }
            }
            return region
        }
        for x in 0..<w { for y in [0, h - 1] where cell[y * w + x] == 0 { _ = fill(y * w + x, mark: 2) } }
        for y in 0..<h { for x in [0, w - 1] where cell[y * w + x] == 0 { _ = fill(y * w + x, mark: 2) } }
        var holes: [CGRect] = []
        for start in 0..<(w * h) where cell[start] == 0 {
            let region = fill(start, mark: 3)
            guard Double(region.count) >= max(2, 0.02 * Double(w * h)) else { continue }
            let xs = region.map { $0 % w }, ys = region.map { $0 / w }
            holes.append(CGRect(x: x0 + xs.min()!, y: y0 + ys.min()!,
                                width: xs.max()! - xs.min()! + 1, height: ys.max()! - ys.min()! + 1))
        }
        return holes
    }
}
