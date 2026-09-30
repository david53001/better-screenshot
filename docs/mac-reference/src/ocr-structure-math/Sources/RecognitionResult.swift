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

/// Pure decision rule for Capture Text. Text lines (one per paragraph, table
/// row or code block after `TextReflow`) join with newlines; blank ones drop.
/// A QR code that fills the selection is what the user was after, so its
/// payload wins; a small one on a poster or slide is appended to the text
/// instead of replacing it.
public enum RecognitionResolver {
    public static func resolve(qrPayloads: [String], textLines: [String], qrDominant: Bool = false) -> RecognitionResult {
        let lines = textLines.filter { !$0.isEmpty }
        if let qr = qrPayloads.first, qrDominant || lines.isEmpty { return .qr(qr) }
        guard !lines.isEmpty else { return .none }
        let text = lines.joined(separator: "\n")
        return .text(([text] + qrPayloads.filter { !text.contains($0) }).joined(separator: "\n"))
    }
}
