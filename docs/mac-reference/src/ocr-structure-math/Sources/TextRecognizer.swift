import Vision
import CoreText
import CoreGraphics
import Foundation

/// Vision wrapper for Capture Text. Synchronous — call it off the main thread
/// (Vision's perform() blocks). Feeds results to RecognitionResolver.
public enum TextRecognizer {
    /// `pointWidth` is the selection's width in screen points; when the capture
    /// is below 2× pixel density the image is upscaled first — measured on the
    /// owner's M3, Vision fragments lines and runs ~60% slower at 1× density.
    /// `math` off (Settings → Capture → Recognize math) skips the pixel passes
    /// that rebuild super/subscripts, roots, fractions and display equations —
    /// the ones that re-run Vision per line — for a faster, Vision-only read.
    public static func recognize(in image: CGImage, pointWidth: CGFloat? = nil, math: Bool = true) throws -> RecognitionResult {
        rereads.withLock { $0.removeAll() }
        defer { rereads.withLock { $0.removeAll() } }
        let factor = pointWidth.map { upscaleFactor(pixelWidth: image.width, pointWidth: $0) } ?? 1
        let source = factor > 1 ? (upscaled(image, by: factor) ?? image) : image

        let textRequest = makeTextRequest()
        let qrRequest = VNDetectBarcodesRequest()
        qrRequest.symbologies = [.qr]

        try VNImageRequestHandler(cgImage: source).perform([textRequest, qrRequest])

        let size = CGSize(width: source.width, height: source.height)
        var lines = reflowLines(textRequest.results ?? [])
        // The read without language correction that code needs (below) runs
        // alongside the rest when Vision's first read already looks like code.
        let rawPass = TextReflow.containsCode(lines, imageSize: size) ? RawPass(source) : nil
        let confidences = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.confidence }
        var absorbed = Set<Int>()
        func pixels(_ b: CGRect) -> CGRect {
            CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
        }
        for i in lines.indices {
            let b = lines[i].box
            let rect = pixels(b)
            // Words Vision boxed on their own beside this line keep their ink —
            // except a detached exponent: short and raised (`nt` of `(1 + r/n)ⁿᵗ`).
            let others = lines.indices.filter { j in
                j != i && (lines[j].text.count > 4 || lines[j].box.midY > b.minY + 0.35 * b.height)
            }.map { pixels(lines[$0].box) }
            // Vision's own read stays in `text` (layout and code go by it); the
            // rebuilt math goes in `recovered` for prose and tables.
            if ScriptRecovery.missingFullStop(lines[i].text, rect: rect, in: source, excluding: others) {
                lines[i].text += "."
            }
            if math, let fixed = ScriptRecovery.relationSymbols(lines[i].text, rect: rect, in: source, excluding: others) {
                lines[i].text = fixed
            }
            if let fixed = ScriptRecovery.dashesAndDots(lines[i].text, rect: rect, in: source, excluding: others) {
                lines[i].text = fixed
            }
            var recovered: String?
            if math && confidences.indices.contains(i) && confidences[i] < 0.9 {
                // A shaky first read (`21120` for `2H₂O`, confidence 0.5) may be
                // replaced by re-reads Vision is sure of.
                var sure = true
                recovered = ScriptRecovery.recover(lines[i].text, rect: rect, in: source, excluding: others,
                                                   confident: false) {
                    let read = readLine($0)
                    if (read?.confidence ?? 0) < 0.9 { sure = false }
                    return read?.text
                }
                if !sure { recovered = nil }
            }
            if math {
                recovered = recovered ?? ScriptRecovery.recover(lines[i].text, rect: rect, in: source,
                                                                excluding: others) { readLine($0)?.text }
            }
            if let text = recovered {
                lines[i].recovered = text
                // An exponent Vision also boxed on its own (`nt` raised beside
                // `(1 + r/n)`) is now part of this line.
                let reach = b.insetBy(dx: -0.3 * b.height, dy: -0.3 * b.height)
                for j in lines.indices where j != i && lines[j].text.count <= 4
                    && reach.contains(CGPoint(x: lines[j].box.midX, y: lines[j].box.midY))
                    && abs(lines[j].box.midY - b.midY) > 0.25 * b.height
                    && (text.contains(ScriptRecovery.script(lines[j].text, superscript: true))
                        || text.contains(ScriptRecovery.script(lines[j].text, superscript: false))) {
                    absorbed.insert(j)
                }
            }
            let shown = lines[i].recovered ?? lines[i].text
            // `log`/`ln` look-alikes on lines no pixel rebuild touched.
            let tidied = TextReflow.separatedVariables(withTimesSigns(ScriptRecovery.repairingLog(shown)))
            if tidied != shown { lines[i].recovered = tidied }
        }
        lines = lines.indices.filter { !absorbed.contains($0) }.map { lines[$0] }
        // Table cells Vision didn't box (a lone `v`, a `2023` header): ink in
        // another cell's column, on a row of text, read on its own.
        for cell in cellLines(lines, in: source) {
            let before = lines.lastIndex { $0.box.midY < cell.box.minY
                || $0.box.maxX < cell.box.minX && abs($0.box.midY - cell.box.midY) < 0.5 * cell.box.height }
            lines.insert(cell, at: before.map { $0 + 1 } ?? 0)
        }
        // Displayed formulas Vision boxed in pieces (limits, stacked fractions).
        if math { lines = DisplayMath.rebuilding(lines, in: source) { readLine($0) } }
        // Language correction "fixes" code into prose (`items.reduce(` →
        // `items. reduce (`, `--parallel` → `-parallel`); when a block reads as
        // code, read the image again without it for those lines.
        if TextReflow.containsCode(lines, imageSize: size) {
            let raw = try (rawPass ?? RawPass(source)).lines()
            for i in lines.indices {
                lines[i].rawText = raw.max { iou($0.box, lines[i].box) < iou($1.box, lines[i].box) }
                    .flatMap { iou($0.box, lines[i].box) > 0.5 ? $0.text : nil }
                // Vision's spaces in monospaced code are guesses (`items ()`,
                // `$curl`); the character cells say where they really are.
                let others = lines.indices.filter { $0 != i }.map { pixels(lines[$0].box) }
                if let spaced = ScriptRecovery.monospaceSpacing(lines[i].rawText ?? lines[i].text,
                                                                rect: pixels(lines[i].box), in: source, excluding: others) {
                    lines[i].rawText = spaced
                }
            }
            // Into reading order: after the last line above it in its column.
            // Closing braces stack (`    }` then `}`): each find widens the
            // search, so look again.
            for _ in 0..<3 {
                let found = bracketLines(lines, in: source)
                for bracket in found {
                    let above = lines.lastIndex { $0.box.midY < bracket.box.midY && $0.box.maxX > bracket.box.minX }
                    lines.insert(bracket, at: above.map { $0 + 1 } ?? 0)
                }
                if found.isEmpty { break }
            }
        }
        let codes = qrRequest.results ?? []
        let qrs = codes.compactMap { $0.payloadStringValue }
        let dominant = codes.contains { $0.boundingBox.width * $0.boundingBox.height >= dominantQRArea }
        var gridLines: GridLines??
        // Without math, stacked fractions aren't looked for (no bar measuring).
        let ruleLength: ((CGRect) -> CGFloat)? = math ? { InkMap(source, rect: $0)?.longestRun() ?? 0 } : nil
        let text = TextReflow.paragraphs(lines, imageSize: size, ruleLength: ruleLength,
                                         verticalRules: { rect in
            if gridLines == nil { gridLines = .some(GridLines(source)) }
            return gridLines??.vertical(in: rect) ?? []
        })
        return RecognitionResolver.resolve(qrPayloads: qrs, textLines: text, qrDominant: dominant)
    }

    /// Vision's read of `image` without language correction, started on a
    /// background thread as soon as it is made.
    private final class RawPass: @unchecked Sendable {
        private let done = DispatchSemaphore(value: 0)
        private var result: Result<[TextReflow.Line], Error> = .success([])

        init(_ image: CGImage) {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let request = makeTextRequest()
                request.usesLanguageCorrection = false
                result = Result {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    return reflowLines(request.results ?? [])
                }
                done.signal()
            }
        }

        func lines() throws -> [TextReflow.Line] {
            done.wait()
            return try result.get()
        }
    }

    /// `3.00 x 10⁸`: a lone x between numbers is a times sign.
    static func withTimesSigns(_ text: String) -> String {
        timesSign.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " × ")
    }

    private static let timesSign = try! NSRegularExpression(pattern: #"(?<=\d) x (?=\d)"#)

    /// Lines holding only brackets (`}`, `{`, `},`), which Vision doesn't box:
    /// ink near the text that no line covers, read on its own.
    private static func bracketLines(_ lines: [TextReflow.Line], in image: CGImage) -> [TextReflow.Line] {
        let size = CGSize(width: image.width, height: image.height)
        let boxes = lines.map { CGRect(x: $0.box.minX * size.width, y: $0.box.minY * size.height,
                                       width: $0.box.width * size.width, height: $0.box.height * size.height) }
        guard let first = boxes.first else { return [] }
        let heights = boxes.map(\.height).sorted()
        let h = heights[heights.count / 2]
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        // A character cell: brackets are centred in theirs, lines start at theirs.
        let cells = zip(boxes, lines).filter { $1.text.count >= 4 }.map { $0.width / CGFloat($1.text.count) }.sorted()
        let cell = cells.isEmpty ? 0.6 * h : cells[cells.count / 2]
        let region = union.insetBy(dx: -h, dy: -1.5 * h).integral.intersection(CGRect(origin: .zero, size: size))
        guard let map = InkMap(image, rect: region) else { return [] }
        let covered = boxes.map { $0.offsetBy(dx: -region.minX, dy: -region.minY).insetBy(dx: -0.3 * h, dy: -0.1 * h) }
        let loose = map.blobs().filter { blob in
            blob.pixels.count >= 3 && !covered.contains { $0.contains(CGPoint(x: blob.box.midX, y: blob.box.midY)) }
        }.sorted { $0.box.minX < $1.box.minX }
        // Loose ink in clusters: pieces that share a row and sit close together.
        var clusters: [[InkMap.Blob]] = []
        for blob in loose {
            if let i = clusters.firstIndex(where: { cluster in
                let box = cluster.dropFirst().reduce(cluster[0].box) { $0.union($1.box) }
                return min(box.maxY, blob.box.maxY) - max(box.minY, blob.box.minY) > 0.3 * min(box.height, blob.box.height)
                    && blob.box.minX - box.maxX < 0.8 * h
            }) {
                clusters[i].append(blob)
            } else {
                clusters.append([blob])
            }
        }
        var found: [TextReflow.Line] = []
        for cluster in clusters {
            let box = cluster.dropFirst().reduce(cluster[0].box) { $0.union($1.box) }
            guard box.height >= 0.5 * h, box.height <= 1.4 * h, box.width <= 2.5 * h else { continue }
            var text = ScriptRecovery.readInk(cluster, width: map.width, capHeight: 0.7 * h, { readLine($0)?.text }) ?? ""
            if text.range(of: #"^[\[\]{}()]{1,3}[,;]?$"#, options: .regularExpression) == nil {
                // Vision reads a lone thin brace as `l` or `)`: go by its outline.
                guard let main = cluster.max(by: { $0.pixels.count < $1.pixels.count }),
                      let shape = ScriptRecovery.brace(main, mapWidth: map.width),
                      cluster.allSatisfy({ $0.box == main.box || $0.box.minX > main.box.maxX && $0.box.height < 0.4 * h })
                else { continue }
                text = String(shape) + (cluster.count > 1 ? "," : "")
            }
            var pixel = box.offsetBy(dx: region.minX, dy: region.minY).insetBy(dx: 0, dy: -(h - box.height) / 2)
            let start = pixel.minX + box.width / CGFloat(max(text.count, 1)) / 2 - cell / 2
            pixel = CGRect(x: start, y: pixel.minY, width: cell * CGFloat(text.count), height: pixel.height)
            found.append(TextReflow.Line(text: text, box: CGRect(x: pixel.minX / size.width, y: pixel.minY / size.height,
                                                                 width: pixel.width / size.width, height: pixel.height / size.height)))
        }
        return found
    }

    /// Ink Vision left unboxed that sits in a table cell: on the row of a line,
    /// clear of it, and under or over another line in some other row.
    private static func cellLines(_ lines: [TextReflow.Line], in image: CGImage) -> [TextReflow.Line] {
        let size = CGSize(width: image.width, height: image.height)
        let boxes = lines.map { CGRect(x: $0.box.minX * size.width, y: $0.box.minY * size.height,
                                       width: $0.box.width * size.width, height: $0.box.height * size.height) }
        // Only a grid has cells: some row holds two lines a gap apart.
        let paired = boxes.contains { a in
            boxes.contains { b in min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0.5 * min(a.height, b.height) && b.minX > a.maxX }
        }
        guard paired, boxes.count >= 3, let first = boxes.first else { return [] }
        let heights = boxes.map(\.height).sorted()
        let h = heights[heights.count / 2]
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        let region = union.insetBy(dx: -3 * h, dy: -0.5 * h).integral.intersection(CGRect(origin: .zero, size: size))
        guard let map = InkMap(image, rect: region) else { return [] }
        let local = boxes.map { $0.offsetBy(dx: -region.minX, dy: -region.minY) }
        let covered = local.map { $0.insetBy(dx: -0.3 * h, dy: -0.15 * h) }
        let blobs = map.blobs()
        let loose = blobs.filter { blob in
            blob.pixels.count >= 3 && blob.box.height <= 1.5 * h && blob.box.width <= 3 * h
                && !covered.contains { $0.intersects(blob.box) }
        }.sorted { $0.box.minX < $1.box.minX }
        var clusters: [[InkMap.Blob]] = []
        for blob in loose {
            if let i = clusters.firstIndex(where: { cluster in
                let box = cluster.dropFirst().reduce(cluster[0].box) { $0.union($1.box) }
                return min(box.maxY, blob.box.maxY) - max(box.minY, blob.box.minY) > 0.3 * min(box.height, blob.box.height)
                    && blob.box.minX - box.maxX < 0.6 * h
            }) {
                clusters[i].append(blob)
            } else {
                clusters.append([blob])
            }
        }
        var found: [TextReflow.Line] = []
        for cluster in clusters {
            let box = cluster.dropFirst().reduce(cluster[0].box) { $0.union($1.box) }
            guard box.height >= 0.35 * h, box.height <= 1.3 * h else { continue }
            func overlap(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat { min(b, d) - max(a, c) }
            // Its row: a line beside it, of a like height, a cell's gap away.
            let row = local.filter { overlap($0.minY, $0.maxY, box.minY, box.maxY) > 0.5 * box.height
                && $0.height < 1.6 * h && $0.height > 0.6 * box.height }
            guard !row.isEmpty, row.allSatisfy({ $0.minX - box.maxX > 0.8 * h || box.minX - $0.maxX > 0.8 * h })
            else { continue }
            // Its column: a line in another row it lines up with.
            guard local.contains(where: { overlap($0.minX, $0.maxX, box.minX, box.maxX) > 0.3 * min($0.width, box.width)
                && overlap($0.minY, $0.maxY, box.minY, box.maxY) < 0 }) else { continue }
            // The row's baseline and cap height, from the ink of the line beside it.
            guard let beside = row.min(by: { abs($0.midX - box.midX) < abs($1.midX - box.midX) }) else { continue }
            let letters = blobs.filter { beside.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
            guard letters.count >= 2 else { continue }
            let bottoms = letters.map(\.box.maxY).sorted()
            let baseline = bottoms[bottoms.count / 2]
            let tops = letters.filter { abs($0.box.maxY - baseline) < 0.1 * h }.map { baseline - $0.box.minY }.sorted()
            guard let capHeight = tops.last else { continue }
            guard var text = ScriptRecovery.readInk(cluster, width: map.width, capHeight: capHeight, baseline: baseline, {
                readLine($0).flatMap { $0.confidence >= 0.5 ? $0.text : nil }
            }), text.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            // A lone `v` is a `V` to Vision; its height says which.
            if text.count == 1, "CKOPSUVWXZ".contains(text), box.height < 0.85 * capHeight { text = text.lowercased() }
            // An italic `v` reads as `y`, but it has no tail below the baseline.
            if text == "y", box.maxY < baseline + 0.1 * capHeight { text = "v" }
            let pixel = box.offsetBy(dx: region.minX, dy: region.minY).insetBy(dx: 0, dy: -max(0, h - box.height) / 2)
            found.append(TextReflow.Line(text: text, box: CGRect(x: pixel.minX / size.width, y: pixel.minY / size.height,
                                                                 width: pixel.width / size.width, height: pixel.height / size.height)))
        }
        return found
    }

    /// A QR code covering this much of the selection is what the user was after.
    static let dominantQRArea: CGFloat = 0.2

    /// Reads a single synthetic line (ScriptRecovery's straightened copy)
    /// without language correction, left to right.
    private static func readLine(_ image: CGImage) -> (text: String, confidence: Float)? {
        // The shaky and confident passes, and DisplayMath's prefixed and bare
        // reads, often paint the very same image: Vision gives the same answer.
        let key = rereadKey(image)
        if let key, let hit = rereads.withLock({ $0[key] }) { return hit }
        let read = uncachedReadLine(image)
        if let key { rereads.withLock { $0[key] = read } }
        return read
    }

    /// Re-reads made during the current capture, by image content.
    private static let rereads = Locked<[RereadKey: (text: String, confidence: Float)?]>([:])

    private struct RereadKey: Hashable {
        let width: Int, height: Int, bytes: Data
    }

    private static func rereadKey(_ image: CGImage) -> RereadKey? {
        guard let data = image.dataProvider?.data else { return nil }
        return RereadKey(width: image.width, height: image.height, bytes: data as Data)
    }

    private static func uncachedReadLine(_ image: CGImage) -> (text: String, confidence: Float)? {
        let request = makeTextRequest()
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let reads = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first }
        let text = reads.map(\.string).joined()
        return text.isEmpty ? nil : (text, reads.map(\.confidence).min() ?? 0)
    }

    /// Vision boxes are normalized with a bottom-left origin; TextReflow wants
    /// top-left, so flip y. Order is kept — it is Vision's reading order.
    private static func reflowLines(_ observations: [VNRecognizedTextObservation]) -> [TextReflow.Line] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let read = candidate.string
            let text = Homoglyphs.latinized(read, keepCyrillic: scripts.cyrillic, keepGreek: scripts.greek,
                                            romanian: scripts.romanian)
            let b = observation.boundingBox
            return TextReflow.Line(text: text, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height),
                                   wordBoxes: wordBoxes(candidate))
        }
    }

    /// Vision's box per word (top-left origin), for the short lines a table
    /// row is made of; a line of prose is never cut into cells, so it skips
    /// the per-word calls.
    private static func wordBoxes(_ candidate: VNRecognizedText) -> [CGRect]? {
        let string = candidate.string
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for i in string.indices {
            if string[i].isWhitespace {
                if let s = start { ranges.append(s..<i); start = nil }
            } else if start == nil {
                start = i
            }
        }
        if let s = start { ranges.append(s..<string.endIndex) }
        guard (2...8).contains(ranges.count) else { return nil }
        var boxes: [CGRect] = []
        for range in ranges {
            guard let b = (try? candidate.boundingBox(for: range))?.boundingBox else { return nil }
            boxes.append(CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
        return boxes
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }

    /// Loads Vision's text model ahead of a real request. Vision drops the
    /// model after ~20s idle and reloading costs 0.5–1s; calling this when the
    /// selection overlay appears hides that behind the user's drag.
    public static func warmUp() {
        // A blank image never reaches the recognizer; a couple of real words
        // load its models (first capture 181 → 142 ms, measured).
        let ctx = CGContext(data: nil, width: 220, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        guard let ctx else { return }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 220, height: 48))
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let words = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Warm up", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        ctx.textPosition = CGPoint(x: 12, y: 14)
        CTLineDraw(words, ctx)
        guard let image = ctx.makeImage() else { return }
        try? VNImageRequestHandler(cgImage: image).perform([makeTextRequest()])
    }

    /// Maps the user's preferred languages (e.g. `en-RO`, `ro-RO`) onto the
    /// locales Vision ships models for, by language code, keeping order and
    /// dropping duplicates. Falls back to `en-US`. Explicit languages replace
    /// `automaticallyDetectsLanguage`, which leaked CJK punctuation into
    /// Latin-script results.
    public static func recognitionLanguages(preferred: [String], supported: [String]) -> [String] {
        var result: [String] = []
        for lang in preferred {
            let code = languageCode(lang)
            guard let match = supported.first(where: { $0 == lang })
                    ?? supported.first(where: { languageCode($0) == code }) else { continue }
            if !result.contains(match) { result.append(match) }
        }
        return result.isEmpty ? ["en-US"] : result
    }

    /// Scale that brings the capture to 2× pixel density; 1 when it already is.
    public static func upscaleFactor(pixelWidth: Int, pointWidth: CGFloat) -> CGFloat {
        guard pixelWidth > 0, pointWidth > 0 else { return 1 }
        return max(1, pointWidth * 2 / CGFloat(pixelWidth))
    }

    private static func makeTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        return request
    }

    private static let languages: [String] = {
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
        return recognitionLanguages(preferred: Locale.preferredLanguages, supported: supported)
    }()

    private static let scripts = Homoglyphs.scripts(in: languages)

    private static func languageCode(_ tag: String) -> String {
        String(tag.prefix { $0 != "-" && $0 != "_" })
    }

    private static func upscaled(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = Int((CGFloat(image.width) * factor).rounded())
        let height = Int((CGFloat(image.height) * factor).rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

/// A value behind a lock (Capture Text runs off the main thread).
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
