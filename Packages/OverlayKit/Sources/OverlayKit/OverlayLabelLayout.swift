import CoreGraphics

/// Pure placement for the small text chips drawn over the capture overlays.
/// All rects are in one view's coordinates, AppKit bottom-left origin.
public enum OverlayLabelLayout {
    /// Where the area-selection size chip goes: just OUTSIDE the selection's top-left
    /// corner (so it never sits on the content being selected); below the bottom-left
    /// corner when there's no room above; inside the top-left corner only when the
    /// selection fills the whole height. Always kept on screen horizontally.
    public static func selectionChipOrigin(selection sel: CGRect, chipSize: CGSize,
                                           bounds: CGRect, gap: CGFloat = 6) -> CGPoint {
        let y: CGFloat
        if sel.maxY + gap + chipSize.height <= bounds.maxY {
            y = sel.maxY + gap
        } else if sel.minY - gap - chipSize.height >= bounds.minY {
            y = sel.minY - gap - chipSize.height
        } else {
            y = sel.maxY - gap - chipSize.height
        }
        let x = min(max(sel.minX, bounds.minX), bounds.maxX - chipSize.width)
        return CGPoint(x: max(x, bounds.minX), y: y)
    }

    /// The window picker's title chip, centred on the hovered window and never wider
    /// than the window minus `margin` on each side. `text` is the rect to draw the
    /// (tail-truncated) title into. nil when the window is too small for any text.
    public static func titleChip(window: CGRect, textSize: CGSize, padding: CGFloat,
                                 margin: CGFloat) -> (chip: CGRect, text: CGRect)? {
        let maxText = window.width - 2 * margin - 2 * padding
        guard maxText >= 24 else { return nil }
        let w = min(textSize.width, maxText)
        let text = CGRect(x: window.midX - w / 2, y: window.midY - textSize.height / 2,
                          width: w, height: textSize.height)
        return (text.insetBy(dx: -padding, dy: -padding), text)
    }
}
