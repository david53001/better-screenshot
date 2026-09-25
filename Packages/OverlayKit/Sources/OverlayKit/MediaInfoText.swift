import Foundation

/// Short captions describing a capture: "1600 × 1000" for a screenshot, "0:42" for a
/// recording, "0:42 · MP4" for the Quick Access recording badge. Used by the card
/// and the History window so both say the same thing the same way.
public enum MediaInfoText {
    /// "0:42", "12:05", "1:02:03" — rounded to the nearest second. nil for a
    /// negative, NaN or infinite length (an unreadable file).
    public static func duration(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// "1600 × 1000" (pixels).
    public static func pixelSize(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }

    /// "0:42 · MP4". Either half is dropped when unknown; nil when both are.
    public static func recordingBadge(seconds: Double?, fileExtension: String) -> String? {
        let parts = [seconds.flatMap(duration), fileExtension.isEmpty ? nil : fileExtension.uppercased()]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
