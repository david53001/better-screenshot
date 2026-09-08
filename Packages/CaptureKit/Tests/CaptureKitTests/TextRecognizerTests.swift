import TestKit
import AppKit
import CoreImage
import Vision
@testable import CaptureKit

// Headless renderers — same technique as the verified 2026-06-04 probe.
private func renderTextImage(_ text: String,
                             size: CGSize = CGSize(width: 600, height: 120)) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor.white)
    ctx.fill(CGRect(origin: .zero, size: size))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    (text as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 36, weight: .medium),
        .foregroundColor: NSColor.black])
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

private func renderQRImage(_ payload: String) -> CGImage {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(payload.data(using: .utf8)!, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    return CIContext().createCGImage(output, from: output.extent)!
}

private func composite(_ left: CGImage, _ right: CGImage) -> CGImage {
    let w = left.width + right.width, h = max(left.height, right.height)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(left, in: CGRect(x: 0, y: 0, width: left.width, height: left.height))
    ctx.draw(right, in: CGRect(x: left.width, y: 0, width: right.width, height: right.height))
    return ctx.makeImage()!
}

/// Vision's barcode detector needs GPU/ANE features that virtualized CI
/// runners lack — it returns no results there while OCR's CPU path still
/// works. Probe Vision directly (independent of TextRecognizer, so a
/// regression in our wrapper still fails on real hardware) and skip the QR
/// cases only where the OS capability is absent.
private let barcodeDetectionAvailable: Bool = {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try? VNImageRequestHandler(cgImage: renderQRImage("probe")).perform([request])
    return !(request.results ?? []).isEmpty
}()

let textRecognizerTests: [TestCase] = {
    var cases = [
        TestCase("languagesMapPreferredOntoVisionSupported") { t in
            let supported = ["en-US", "fr-FR", "ro-RO", "de-DE"]
            t.equal(TextRecognizer.recognitionLanguages(preferred: ["en-RO", "ro-RO"], supported: supported),
                    ["en-US", "ro-RO"])
            // Unsupported languages drop; duplicates collapse; order is kept.
            t.equal(TextRecognizer.recognitionLanguages(preferred: ["hu-HU", "fr-CA", "en-GB", "en-US"], supported: supported),
                    ["fr-FR", "en-US"])
        },
        TestCase("languagesFallBackToEnglish") { t in
            t.equal(TextRecognizer.recognitionLanguages(preferred: ["hu-HU"], supported: ["en-US", "fr-FR"]), ["en-US"])
            t.equal(TextRecognizer.recognitionLanguages(preferred: [], supported: ["en-US"]), ["en-US"])
        },
        TestCase("upscaleFactorBringsDensityToTwo") { t in
            t.equal(TextRecognizer.upscaleFactor(pixelWidth: 800, pointWidth: 400), 1)   // retina: untouched
            t.equal(TextRecognizer.upscaleFactor(pixelWidth: 1600, pointWidth: 400), 1)  // denser than 2x: untouched
            t.equal(TextRecognizer.upscaleFactor(pixelWidth: 400, pointWidth: 400), 2)   // 1x display
            t.equal(TextRecognizer.upscaleFactor(pixelWidth: 600, pointWidth: 400), 4.0 / 3.0) // stretched 1.5x
            t.equal(TextRecognizer.upscaleFactor(pixelWidth: 400, pointWidth: 0), 1)     // degenerate
        },
        TestCase("recognizesRenderedText") { t in
            do {
                let result = try TextRecognizer.recognize(
                    in: renderTextImage("Hello BetterScreenshot 12345"))
                guard case .text(let s) = result else {
                    t.fail("expected .text, got \(result)"); return
                }
                t.isTrue(s.contains("BetterScreenshot"), "recognized: \(s)")
                t.isTrue(s.contains("12345"), "recognized: \(s)")
            } catch {
                t.fail("TextRecognizer threw: \(error)")
            }
        },
        TestCase("blankImageIsNone") { t in
            do {
                let result = try TextRecognizer.recognize(in: renderTextImage(""))
                t.equal(result, RecognitionResult.none)
            } catch {
                t.fail("TextRecognizer threw: \(error)")
            }
        },
    ]
    if barcodeDetectionAvailable {
        cases += [
            TestCase("decodesQRPayload") { t in
                do {
                    let result = try TextRecognizer.recognize(
                        in: renderQRImage("https://github.com/david53001/BetterScreenshot"))
                    t.equal(result, RecognitionResult.qr("https://github.com/david53001/BetterScreenshot"))
                } catch {
                    t.fail("TextRecognizer threw: \(error)")
                }
            },
            TestCase("qrBeatsTextInMixedImage") { t in
                do {
                    let mixed = composite(renderTextImage("plain words"), renderQRImage("qr-payload"))
                    let result = try TextRecognizer.recognize(in: mixed)
                    t.equal(result, RecognitionResult.qr("qr-payload"))
                } catch {
                    t.fail("TextRecognizer threw: \(error)")
                }
            },
        ]
    } else {
        print("⚠ QR decode tests skipped — Vision barcode detection unavailable in this environment")
    }
    return cases
}()
