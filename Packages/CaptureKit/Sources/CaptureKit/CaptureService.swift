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

    /// `excludingWindowIDs`: on-screen windows left out of the image — the app passes its guided-tour
    /// tag windows, so a tag never ends up in the user's screenshot. Full screen and area captures
    /// filter them out. A window capture records the window *with its child windows*, and a tag is a
    /// child window of the window it explains, so when an excluded window belongs to the captured
    /// window's app, that capture leaves child windows out (macOS 14.2+; earlier systems can't).
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
            guard let cropped = FrozenScreen(displayID: displayID, image: full, displayFrame: display.frame)
                .crop(rect)
            else { throw CaptureError.cropFailed }
            return cropped

        case let .window(windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID })
            else { throw CaptureError.windowNotFound }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            let app = window.owningApplication?.processID
            if #available(macOS 14.2, *), app != nil,
               hidden.contains(where: { $0.owningApplication?.processID == app }) {
                config.includeChildWindows = false
            }
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        }
    }

    /// Every display as it looks right now (`FrozenScreen`), grabbed together — for an area capture
    /// that freezes the screen while the user selects.
    ///
    /// The selection overlay is already up when this runs, and a window ordered front a moment ago is
    /// sometimes missing from `SCShareableContent` — excluded by ID only, its dim was baked into the shot.
    /// So our own app is excluded as a whole (applied at grab time, listed or not) and only our *listed*
    /// windows outside `excludingWindowIDs` are let back in.
    public func freezeDisplays(excludingWindowIDs: Set<CGWindowID> = []) async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        let hidden = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let pid = ProcessInfo.processInfo.processIdentifier
        let me = content.applications.first { $0.processID == pid }
        let kept = content.windows.filter {
            $0.owningApplication?.processID == pid && !excludingWindowIDs.contains($0.windowID)
        }
        return try await withThrowingTaskGroup(of: FrozenScreen.self) { group in
            for display in content.displays {
                var (filter, config) = try displayFilter(display.displayID, content: content, hiding: hidden)
                if let me {
                    filter = SCContentFilter(display: display, excludingApplications: [me], exceptingWindows: kept)
                }
                group.addTask {
                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: filter, configuration: config)
                    return FrozenScreen(displayID: display.displayID, image: image, displayFrame: display.frame)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
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
