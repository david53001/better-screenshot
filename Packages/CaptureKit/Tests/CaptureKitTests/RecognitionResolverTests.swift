import TestKit
@testable import CaptureKit

let recognitionResolverTests: [TestCase] = [
    TestCase("aQRCodeFillingTheSelectionBeatsText") { t in
        let r = RecognitionResolver.resolve(qrPayloads: ["https://example.com"],
                                            textLines: ["Scan me"], qrDominant: true)
        t.equal(r, RecognitionResult.qr("https://example.com"))
    },
    TestCase("aSmallQRCodeIsAppendedToTheText") { t in
        // A poster with a QR in the corner keeps its text.
        let r = RecognitionResolver.resolve(qrPayloads: ["https://example.com"], textLines: ["hello", "world"])
        t.equal(r, RecognitionResult.text("hello\nworld\nhttps://example.com"))
    },
    TestCase("aQRPayloadAlreadyPrintedIsNotRepeated") { t in
        let r = RecognitionResolver.resolve(qrPayloads: ["example.com/join"], textLines: ["Join at example.com/join"])
        t.equal(r, RecognitionResult.text("Join at example.com/join"))
    },
    TestCase("aQRCodeAloneIsTheResult") { t in
        t.equal(RecognitionResolver.resolve(qrPayloads: ["x"], textLines: []), RecognitionResult.qr("x"))
    },
    TestCase("textLinesJoinWithNewlines") { t in
        let r = RecognitionResolver.resolve(qrPayloads: [], textLines: ["hello", "world"])
        t.equal(r, RecognitionResult.text("hello\nworld"))
    },
    TestCase("blankLinesAreDropped") { t in
        let r = RecognitionResolver.resolve(qrPayloads: [], textLines: ["", "hello", ""])
        t.equal(r, RecognitionResult.text("hello"))
    },
    TestCase("nothingIsNone") { t in
        t.equal(RecognitionResolver.resolve(qrPayloads: [], textLines: []),
                RecognitionResult.none)
        t.equal(RecognitionResolver.resolve(qrPayloads: [], textLines: ["", ""]),
                RecognitionResult.none)
    },
    TestCase("clipboardStrings") { t in
        t.equal(RecognitionResult.qr("x").clipboardString, "x")
        t.equal(RecognitionResult.text("y").clipboardString, "y")
        t.isNil(RecognitionResult.none.clipboardString)
    },
    TestCase("hudMessages") { t in
        t.equal(RecognitionResult.qr("x").hudMessage, "QR code copied")
        t.equal(RecognitionResult.text("abcd").hudMessage, "Text copied — 4 characters")
        t.equal(RecognitionResult.none.hudMessage, "No text found")
    },
]
