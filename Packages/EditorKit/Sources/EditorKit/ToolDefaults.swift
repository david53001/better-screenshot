import CoreGraphics

public extension AnnotationStyle {
    /// This style with `other`'s redaction, highlighter-pen and spotlight settings. Every object's
    /// style carries a copy of those sticky defaults from when it was drawn; when an object's style
    /// becomes the default (opening a text for editing), they must stay the user's current ones,
    /// not roll back to that old copy.
    func keepingToolDefaults(of other: AnnotationStyle) -> AnnotationStyle {
        var s = self
        s.redactionMode = other.redactionMode
        s.blurRadius = other.blurRadius
        s.pixelSize = other.pixelSize
        s.highlighterPen = other.highlighterPen
        s.spotlightShape = other.spotlightShape
        s.spotlightDim = other.spotlightDim
        return s
    }
}
