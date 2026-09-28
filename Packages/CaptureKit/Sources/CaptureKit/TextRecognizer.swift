import Vision
import CoreGraphics
import Foundation

/// Vision wrapper for Capture Text. Synchronous — call it off the main thread
/// (Vision's perform() blocks). Feeds results to RecognitionResolver.
public enum TextRecognizer {
    /// `pointWidth` is the selection's width in screen points; when the capture
    /// is below 2× pixel density the image is upscaled first — measured on the
    /// owner's M3, Vision fragments lines and runs ~60% slower at 1× density.
    public static func recognize(in image: CGImage, pointWidth: CGFloat? = nil) throws -> RecognitionResult {
        let factor = pointWidth.map { upscaleFactor(pixelWidth: image.width, pointWidth: $0) } ?? 1
        let source = factor > 1 ? (upscaled(image, by: factor) ?? image) : image

        let textRequest = makeTextRequest()
        let qrRequest = VNDetectBarcodesRequest()
        qrRequest.symbologies = [.qr]

        try VNImageRequestHandler(cgImage: source).perform([textRequest, qrRequest])

        let size = CGSize(width: source.width, height: source.height)
        var lines = reflowLines(textRequest.results ?? [])
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
            var recovered: String?
            if confidences.indices.contains(i) && confidences[i] < 0.9 {
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
            recovered = recovered ?? ScriptRecovery.recover(lines[i].text, rect: rect, in: source,
                                                                  excluding: others) { readLine($0)?.text }
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
            if withTimesSigns(shown) != shown { lines[i].recovered = withTimesSigns(shown) }
        }
        lines = lines.indices.filter { !absorbed.contains($0) }.map { lines[$0] }
        // Language correction "fixes" code into prose (`items.reduce(` →
        // `items. reduce (`, `--parallel` → `-parallel`); when a block reads as
        // code, read the image again without it for those lines.
        if TextReflow.containsCode(lines, imageSize: size) {
            let rawRequest = makeTextRequest()
            rawRequest.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: source).perform([rawRequest])
            let raw = reflowLines(rawRequest.results ?? [])
            for i in lines.indices {
                lines[i].rawText = raw.max { iou($0.box, lines[i].box) < iou($1.box, lines[i].box) }
                    .flatMap { iou($0.box, lines[i].box) > 0.5 ? $0.text : nil }
            }
        }
        let codes = qrRequest.results ?? []
        let qrs = codes.compactMap { $0.payloadStringValue }
        let dominant = codes.contains { $0.boundingBox.width * $0.boundingBox.height >= dominantQRArea }
        let text = TextReflow.paragraphs(lines, imageSize: size) { InkMap(source, rect: $0)?.longestRun() ?? 0 }
        return RecognitionResolver.resolve(qrPayloads: qrs, textLines: text, qrDominant: dominant)
    }

    /// `3.00 x 10⁸`: a lone x between numbers is a times sign.
    static func withTimesSigns(_ text: String) -> String {
        timesSign.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " × ")
    }

    private static let timesSign = try! NSRegularExpression(pattern: #"(?<=\d) x (?=\d)"#)

    /// A QR code covering this much of the selection is what the user was after.
    static let dominantQRArea: CGFloat = 0.2

    /// Reads a single synthetic line (ScriptRecovery's straightened copy)
    /// without language correction, left to right.
    private static func readLine(_ image: CGImage) -> (text: String, confidence: Float)? {
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
            guard let read = observation.topCandidates(1).first?.string else { return nil }
            let text = Homoglyphs.latinized(read, keepCyrillic: scripts.cyrillic, keepGreek: scripts.greek)
            let b = observation.boundingBox
            return TextReflow.Line(text: text, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
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
        let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = ctx?.makeImage() else { return }
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
