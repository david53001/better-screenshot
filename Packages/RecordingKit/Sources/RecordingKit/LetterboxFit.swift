import CoreGraphics

/// Where retargeted content lands in the fixed-size recording: scaled to fit
/// with its aspect ratio kept, centred, black bars on the other axis. Used as
/// `SCStreamConfiguration.destinationRect` — window streams otherwise pin
/// the scaled window to the top-left corner.
public enum LetterboxFit {
    /// The fitted rect in output pixels (top-left origin), rounded to whole pixels.
    /// Degenerate content fills the whole output.
    public static func rect(content: CGSize, output: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return CGRect(origin: .zero, size: output) }
        let scale = min(output.width / content.width, output.height / content.height)
        let w = min(output.width, (content.width * scale).rounded())
        let h = min(output.height, (content.height * scale).rounded())
        return CGRect(x: ((output.width - w) / 2).rounded(.down),
                      y: ((output.height - h) / 2).rounded(.down), width: w, height: h)
    }
}
