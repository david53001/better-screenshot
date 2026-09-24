import CoreImage
import CoreGraphics

public enum Redactor {
    private static let context = CIContext(options: nil)

    /// Filters `region` (top-left image px, snapped outward to whole pixels and clipped to the
    /// image), reading up to `margin` px of the real image around it. Crops the CGImage first —
    /// cheap, it shares the pixel data — so CoreImage uploads just that area, not the whole
    /// screenshot, on every re-render (a redaction re-renders on each tick of a move / resize /
    /// strength drag). `transform` gets the source image and the region's rect in its (bottom-left
    /// origin) coordinates.
    private static func patch(_ base: CGImage, region: CGRect, margin: CGFloat = 0,
                              _ transform: (CIImage, CGRect) -> CIImage) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let r = region.integral.intersection(bounds)
        guard r.width >= 1, r.height >= 1 else { return nil }
        let area = r.insetBy(dx: -margin, dy: -margin).integral.intersection(bounds)
        guard let crop = base.cropping(to: area) else { return nil }
        let img = CIImage(cgImage: crop)   // extent (0, 0, area.w, area.h), y up
        let out = CGRect(x: r.minX - area.minX, y: area.maxY - r.maxY, width: r.width, height: r.height)
        return context.createCGImage(transform(img, out).cropped(to: out), from: out)
    }

    public static func pixelate(_ base: CGImage, region: CGRect, blockSize: CGFloat) -> CGImage? {
        patch(base, region: region) { img, out in
            // Only the region's own pixels; clamped so edge blocks sample real pixels rather
            // than transparency. CIPixellate takes one sample per block, so a box blur the size
            // of a block goes first — each block shows its average colour (a classic mosaic),
            // not whichever pixel of a letter its centre happened to land on. Blocks are
            // centred on the region's centre.
            img.clampedToExtent()
                .applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: blockSize / 2])
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: blockSize,
                    kCIInputCenterKey: CIVector(x: out.midX, y: out.midY)])
        }
    }

    public static func blur(_ base: CGImage, region: CGRect, radius: CGFloat) -> CGImage? {
        // Blurs with the real pixels around the box (the Gaussian reaches ~3 × radius), so a
        // strong blur has no streaks from smeared edge pixels; clamped only at the image's edge.
        patch(base, region: region, margin: ceil(radius * 3)) { img, _ in
            img.clampedToExtent().applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius])
        }
    }
}
