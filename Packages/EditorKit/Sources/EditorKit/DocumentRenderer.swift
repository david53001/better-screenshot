import AppKit
import CoreGraphics

public enum DocumentRenderer {
    /// Flattens the document into a CGImage. Used for both export and the canvas.
    /// `preview` is an optional in-progress annotation drawn on top of the
    /// committed ones (live drag feedback); it is never added to the document.
    public static func render(_ doc: EditorDocument, preview: (any Annotation)? = nil) -> CGImage? {
        let w = doc.baseImage.width, h = doc.baseImage.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // We want a top-left origin (so annotation coords match the canvas and
        // text is upright). `flipped: true` only sets the isFlipped *flag* — it
        // does not transform the CTM — so on its own NSImage.draw renders the
        // base upside-down. Applying the flip transform too makes this context
        // behave exactly like a real flipped NSView (base right-side-up).
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        NSImage(cgImage: doc.baseImage, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        AnnotationPainter.draw(doc.annotations + [preview].compactMap { $0 }, imageSize: doc.size)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
