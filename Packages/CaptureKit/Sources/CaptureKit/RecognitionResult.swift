/// What Capture Text found in the selected region.
public enum RecognitionResult: Equatable {
    case qr(String)
    case text(String)
    case none

    /// The string to put on the clipboard (nil = copy nothing).
    public var clipboardString: String? {
        switch self {
        case .qr(let s): return s
        case .text(let s): return s
        case .none: return nil
        }
    }

    /// Confirmation HUD message.
    public var hudMessage: String {
        switch self {
        case .qr: return "QR code copied"
        case .text(let s): return "Text copied — \(s.count) characters"
        case .none: return "No text found"
        }
    }
}

/// Pure decision rule for Capture Text: any QR code wins over recognized text;
/// text lines (one per paragraph after `TextReflow`) join with newlines; blank
/// lines drop.
public enum RecognitionResolver {
    public static func resolve(qrPayloads: [String], textLines: [String]) -> RecognitionResult {
        if let qr = qrPayloads.first { return .qr(qr) }
        let lines = textLines.filter { !$0.isEmpty }
        return lines.isEmpty ? .none : .text(lines.joined(separator: "\n"))
    }
}
