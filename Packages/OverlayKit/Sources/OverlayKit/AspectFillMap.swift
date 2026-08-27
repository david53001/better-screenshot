import CoreGraphics

/// Card-space ↔ image-pixel-space mapping for a full-bleed aspect-fill thumbnail.
/// Sampling the pixels behind the button row means knowing which part of the source
/// image the card actually shows — aspect-fill crops one axis away entirely.
public enum AspectFillMap {
    /// Maps a rect in card/point space to the source-image PIXEL rect that
    /// `CALayer.contentsGravity = .resizeAspectFill` draws into it.
    /// Both spaces use a TOP-LEFT origin. Returns .zero for degenerate inputs.
    public static func sourceRect(cardSize: CGSize,
                                  imagePixelSize: CGSize,
                                  cardRect: CGRect) -> CGRect {
        guard cardSize.width > 0, cardSize.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0,
              cardRect.width > 0, cardRect.height > 0 else { return .zero }

        // Aspect-fill scales until both axes are covered, then centres the overflow.
        let scale = max(cardSize.width / imagePixelSize.width,
                        cardSize.height / imagePixelSize.height)
        let offsetX = (cardSize.width - imagePixelSize.width * scale) / 2
        let offsetY = (cardSize.height - imagePixelSize.height * scale) / 2

        let minX = (cardRect.minX - offsetX) / scale
        let minY = (cardRect.minY - offsetY) / scale
        let maxX = (cardRect.maxX - offsetX) / scale
        let maxY = (cardRect.maxY - offsetY) / scale

        // Clamp: a card rect can hang off the edge, but there are no pixels out there.
        let x0 = min(max(minX, 0), imagePixelSize.width)
        let y0 = min(max(minY, 0), imagePixelSize.height)
        let x1 = min(max(maxX, 0), imagePixelSize.width)
        let y1 = min(max(maxY, 0), imagePixelSize.height)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
