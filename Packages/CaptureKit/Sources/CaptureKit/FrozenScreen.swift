import CoreGraphics

/// One display's image, grabbed the moment an area capture starts ("freeze screen", owner 2026-09-30):
/// the selection overlay shows it instead of the live screen, and the screenshot is cut from it — so the
/// shot is the screen at the moment the hotkey was pressed, however long the user takes to drag.
public struct FrozenScreen {
    public let displayID: CGDirectDisplayID
    /// The whole display, top-left origin, at `image.width / displayFrame.width` pixels per point.
    public let image: CGImage
    /// The display's frame in points, as `CaptureGeometry.pixelRect` expects it.
    public let displayFrame: CGRect

    public init(displayID: CGDirectDisplayID, image: CGImage, displayFrame: CGRect) {
        self.displayID = displayID
        self.image = image
        self.displayFrame = displayFrame
    }

    /// The part of the frozen display under `globalRect` (Cocoa global points); nil if it misses the display.
    public func crop(_ globalRect: CGRect) -> CGImage? {
        guard displayFrame.width > 0 else { return nil }
        let scale = CGFloat(image.width) / displayFrame.width
        return ImageCropper.crop(image, to: CaptureGeometry.pixelRect(
            forGlobalRect: globalRect, inDisplayFrame: displayFrame, scale: scale))
    }
}
