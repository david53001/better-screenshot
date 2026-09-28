import AppKit
import CoreImage
import Vision
import VisionKit
import CaptureKit

// MARK: - QR codes (generated locally, embedded as data: URIs)

func qrDataURI(_ payload: String) -> String {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(Data(payload.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    let cg = CIContext().createCGImage(scaled, from: scaled.extent)!
    let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    return "data:image/png;base64," + data.base64EncodedString()
}

func expandQRPlaceholders(_ html: String) -> String {
    var out = html
    while let start = out.range(of: "{{QR:"), let end = out.range(of: "}}", range: start.upperBound..<out.endIndex) {
        let payload = String(out[start.upperBound..<end.lowerBound])
        out.replaceSubrange(start.lowerBound..<end.upperBound, with: qrDataURI(payload))
    }
    return out
}

// MARK: - Run-loop helper

func pumpUntil(timeout: TimeInterval, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done() {
        if Date() > deadline { return false }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return true
}

// MARK: - macOS Live Text baseline (VisionKit ImageAnalyzer) — comparison only

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

func liveTextTranscript(_ image: CGImage) -> String? {
    let result = Box<String??>(nil)
    let img = image
    Task.detached {
        do {
            let analyzer = ImageAnalyzer()
            let analysis = try await analyzer.analyze(img, orientation: .up,
                                                      configuration: ImageAnalyzer.Configuration([.text]))
            result.value = .some(analysis.transcript)
        } catch {
            result.value = .some(nil)
        }
    }
    _ = pumpUntil(timeout: 30) { result.value != nil }
    guard let r = result.value, let t = r, !t.isEmpty else { return nil }
    return t
}

// MARK: - Raw Vision dump (fix-relevant data: candidates + per-character boxes)

func dumpVision(_ image: CGImage, density: Int) {
    let pointWidth = CGFloat(image.width) / CGFloat(density)
    let factor = TextRecognizer.upscaleFactor(pixelWidth: image.width, pointWidth: pointWidth)
    let source = factor > 1 ? (upscale(image, by: factor) ?? image) : image
    let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
    let langs = TextRecognizer.recognitionLanguages(preferred: Locale.preferredLanguages, supported: supported)
    print("  image \(image.width)x\(image.height) px, density \(density)x, upscale \(factor), languages \(langs)")

    for correction in [true, false] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = correction
        request.recognitionLanguages = langs
        try? VNImageRequestHandler(cgImage: source).perform([request])
        print("  --- usesLanguageCorrection = \(correction): \(request.results?.count ?? 0) observations")
        for obs in request.results ?? [] {
            let b = obs.boundingBox
            let top = 1 - b.maxY
            print(String(format: "  OBS box x=%.3f y(top)=%.3f w=%.3f h=%.3f", b.minX, top, b.width, b.height))
            for (i, cand) in obs.topCandidates(3).enumerated() {
                print(String(format: "    cand%d conf=%.2f  %@", i, cand.confidence, cand.string.debugDescription))
            }
            guard correction, let best = obs.topCandidates(1).first else { continue }
            // Per-character boxes relative to the line: dy = (lineMidY - charMidY)/lineH (positive = raised),
            // hr = charH / lineH. A superscript shows up as dy > 0 and hr < 1.
            var parts: [String] = []
            var idx = best.string.startIndex
            while idx < best.string.endIndex {
                let next = best.string.index(after: idx)
                let ch = best.string[idx]
                if !ch.isWhitespace, let box = try? best.boundingBox(for: idx..<next) {
                    let r = box.boundingBox
                    let dy = (r.midY - b.midY) / b.height
                    let hr = r.height / b.height
                    parts.append(String(format: "%@[dy%+.2f h%.2f x%.3f-%.3f]", String(ch), dy, hr, r.minX, r.maxX))
                }
                idx = next
            }
            print("    chars: " + parts.joined(separator: " "))
        }
    }
}

func upscale(_ image: CGImage, by factor: CGFloat) -> CGImage? {
    let w = Int((CGFloat(image.width) * factor).rounded()), h = Int((CGFloat(image.height) * factor).rounded())
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

// MARK: - Raw Vision baseline: same request as the app, observations in Vision's own
// order, one per line, no TextReflow — shows what the reflow step adds or loses.

func rawVisionText(_ image: CGImage, density: Int) -> String? {
    let pointWidth = CGFloat(image.width) / CGFloat(density)
    let factor = TextRecognizer.upscaleFactor(pixelWidth: image.width, pointWidth: pointWidth)
    let source = factor > 1 ? (upscale(image, by: factor) ?? image) : image
    let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = TextRecognizer.recognitionLanguages(preferred: Locale.preferredLanguages, supported: supported)
    try? VNImageRequestHandler(cgImage: source).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
}
