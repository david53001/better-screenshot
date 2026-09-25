import ScreenCaptureKit
import CoreGraphics

public enum CaptureError: Error {
    case noShareableContent
    case displayNotFound
    case windowNotFound
    case cropFailed
}

public struct CaptureService {
    public init() {}

    /// `excludingWindowIDs`: on-screen windows left out of full-screen and area captures — the app
    /// passes its guided-tour tag windows, so a tag never ends up in the user's screenshot. (A window
    /// capture records only that one window, so it needs no exclusions.)
    public func capture(_ target: CaptureTarget,
                        excludingWindowIDs: Set<CGWindowID> = []) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        let hidden = content.windows.filter { excludingWindowIDs.contains($0.windowID) }

        switch target {
        case let .fullscreen(displayID):
            let (filter, config) = try displayFilter(displayID, content: content, hiding: hidden)
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)

        case let .area(rect, displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw CaptureError.displayNotFound }
            let (filter, config) = try displayFilter(displayID, content: content, hiding: hidden)
            let full = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            let scale = CGFloat(full.width) / CGFloat(display.width)
            let pixelRect = CaptureGeometry.pixelRect(
                forGlobalRect: rect, inDisplayFrame: display.frame, scale: scale)
            guard let cropped = ImageCropper.crop(full, to: pixelRect)
            else { throw CaptureError.cropFailed }
            return cropped

        case let .window(windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID })
            else { throw CaptureError.windowNotFound }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        }
    }

    private func displayFilter(_ displayID: CGDirectDisplayID,
                               content: SCShareableContent, hiding hidden: [SCWindow])
        throws -> (SCContentFilter, SCStreamConfiguration) {
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw CaptureError.displayNotFound }
        let filter = SCContentFilter(display: display, excludingWindows: hidden)
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * 2)   // capture at @2x; refined later
        config.height = Int(CGFloat(display.height) * 2)
        config.showsCursor = false
        return (filter, config)
    }
}
