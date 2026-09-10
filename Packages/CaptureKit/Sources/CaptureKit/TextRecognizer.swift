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

        // Vision boxes are normalized with a bottom-left origin; TextReflow
        // wants top-left, so flip y.
        let lines = (textRequest.results ?? []).compactMap { observation -> TextReflow.Line? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let b = observation.boundingBox
            return TextReflow.Line(text: text, box: CGRect(x: b.minX, y: 1 - b.maxY,
                                                           width: b.width, height: b.height))
        }
        let qrs = (qrRequest.results ?? []).compactMap { $0.payloadStringValue }
        return RecognitionResolver.resolve(qrPayloads: qrs, textLines: TextReflow.paragraphs(lines))
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
