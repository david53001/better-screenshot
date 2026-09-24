import AppKit

/// How a redaction hides what's under it.
public enum RedactionMode: String, Codable, CaseIterable {
    case blur, pixelate
}

/// A redaction box. Its patch is rendered from `source` (the document's base image) for the
/// box's *current* frame and strength, so moving or resizing it redacts what is under it now —
/// the patch used to be baked once at creation, so a moved blur showed the old area's pixels.
/// The mode and strength live in `style` (`redactionMode`, `blurRadius`, `pixelSize`), so the
/// panel's style edits restyle and convert selected redactions like any other object.
public struct RedactionAnnotation: Annotation {
    public let id = UUID()
    /// Always opaque — a translucent redaction would show what it hides.
    public var style: AnnotationStyle { didSet { if style.opacity != 1 { style.opacity = 1 } } }
    public var frame: CGRect
    /// The image the patch is rendered from; `EditorDocument.cropped` swaps in the cropped base.
    public var source: CGImage
    /// The last rendered patch, shared by this value's copies: redraws that change neither the
    /// frame nor the strength (another object moving, a selection change) reuse it.
    private let cache = PatchCache()

    public init(frame: CGRect, source: CGImage, style: AnnotationStyle = .default) {
        self.frame = frame; self.source = source; self.style = style
        self.style.opacity = 1
    }

    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }

    /// Where the patch is drawn: the frame snapped outward to whole pixels (so no sliver of the
    /// original shows at a fractional edge), within the image.
    public var patchRect: CGRect {
        frame.integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
    }

    /// The redacted pixels for the current frame, mode and strength.
    public func patch() -> CGImage? {
        let rect = patchRect
        guard !rect.isEmpty else { return nil }
        let key = PatchCache.Key(source: source, rect: rect, mode: style.redactionMode,
                                 strength: style.redactionStrength)
        if let hit = cache.patch(for: key) { return hit }
        let patch: CGImage?
        switch style.redactionMode {
        case .blur: patch = Redactor.blur(source, region: rect, radius: style.blurRadius)
        case .pixelate: patch = Redactor.pixelate(source, region: rect, blockSize: style.pixelSize)
        }
        cache.store(patch, for: key)
        return patch
    }

    public func draw() {
        guard let patch = patch() else { return }
        let r = patchRect
        NSImage(cgImage: patch, size: r.size).draw(in: r)
    }
}

public extension AnnotationStyle {
    static let blurRadiusRange: ClosedRange<CGFloat> = 2...40
    static let pixelSizeRange: ClosedRange<CGFloat> = 4...48

    /// The strength of the current redaction mode, in image px (blur radius / pixel size).
    var redactionStrength: CGFloat {
        switch redactionMode {
        case .blur: return blurRadius
        case .pixelate: return pixelSize
        }
    }
}

/// One-entry memo of a redaction's last patch.
private final class PatchCache {
    struct Key {
        let source: CGImage, rect: CGRect, mode: RedactionMode, strength: CGFloat
        func matches(_ o: Key) -> Bool {
            source === o.source && rect == o.rect && mode == o.mode && strength == o.strength
        }
    }
    private var key: Key?
    private var image: CGImage?

    func patch(for k: Key) -> CGImage? {
        guard let key, key.matches(k) else { return nil }
        return image
    }
    func store(_ image: CGImage?, for k: Key) { key = k; self.image = image }
}

public extension RedactionMode {
    /// The tool that draws this mode.
    var tool: EditorTool {
        switch self {
        case .blur: return .blur
        case .pixelate: return .pixelate
        }
    }
}

public extension EditorTool {
    /// The redaction mode this tool draws, or nil for non-redaction tools.
    var redactionMode: RedactionMode? { RedactionMode.allCases.first { $0.tool == self } }
}
