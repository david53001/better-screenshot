import CoreImage
import CoreGraphics

public enum Redactor {
    private static let context = CIContext(options: nil)

    /// Filters `region` (top-left image px, snapped outward to whole pixels and clipped to the
    /// image) using only the pixels inside it. Crops the CGImage first — cheap, it shares the
    /// pixel data — so CoreImage uploads just the region, not the whole screenshot, on every
    /// re-render (a redaction re-renders on each tick of a move / resize / strength drag).
    private static func patch(_ base: CGImage, region: CGRect,
                              _ transform: (CIImage) -> CIImage) -> CGImage? {
        let r = region.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard r.width >= 1, r.height >= 1, let crop = base.cropping(to: r) else { return nil }
        let img = CIImage(cgImage: crop)   // extent (0, 0, w, h)
        return context.createCGImage(transform(img).cropped(to: img.extent), from: img.extent)
    }

    public static func pixelate(_ base: CGImage, region: CGRect, blockSize: CGFloat) -> CGImage? {
        patch(base, region: region) { img in
            // Clamped so edge blocks sample real pixels rather than transparency; blocks are
            // centred on the region's centre.
            img.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: blockSize,
                kCIInputCenterKey: CIVector(x: img.extent.midX, y: img.extent.midY)])
        }
    }

    public static func blur(_ base: CGImage, region: CGRect, radius: CGFloat) -> CGImage? {
        patch(base, region: region) { img in
            img.clampedToExtent().applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius])
        }
    }
}
