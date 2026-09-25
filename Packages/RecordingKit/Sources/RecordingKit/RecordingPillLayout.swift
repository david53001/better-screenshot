import CoreGraphics

/// Pure geometry for the live recording pill (`App/Recording/RecordingControlsController`).
public enum RecordingPillLayout {
    /// Width of each of the Restart / Discard icon buttons, chosen so either confirm label
    /// ("Restart?" / "Discard?", `confirmWidths`) fits the pair's combined slot. While one
    /// confirms it fills that slot and the other hides, so the pill's width never changes
    /// (UI review P1: it grew ~44pt and, anchored on the right, its left edge jumped).
    public static func confirmPairButtonWidth(confirmWidths: [CGFloat], spacing: CGFloat,
                                              minimum: CGFloat) -> CGFloat {
        max(minimum, (((confirmWidths.max() ?? 0) - spacing) / 2).rounded(.up))
    }

    /// The combined slot a confirming button fills: both buttons plus the gap between them.
    public static func confirmSlotWidth(buttonWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        2 * buttonWidth + spacing
    }

    /// Where the hover hint bubble goes (screen coordinates): centred over the hovered
    /// button's `anchorX`, `gap` above the pill — below it when there's no room above —
    /// and at least `margin` inside `visible` horizontally (narrowed to fit if needed).
    public static func hintFrame(size: CGSize, anchorX: CGFloat, pill: CGRect, visible: CGRect,
                                 gap: CGFloat, margin: CGFloat) -> CGRect {
        let above = pill.maxY + gap + size.height <= visible.maxY
        let y = above ? pill.maxY + gap : pill.minY - gap - size.height
        let width = min(size.width, visible.width - 2 * margin)
        let x = min(max(anchorX - width / 2, visible.minX + margin), visible.maxX - margin - width)
        return CGRect(x: x.rounded(), y: y, width: width, height: size.height)
    }
}
