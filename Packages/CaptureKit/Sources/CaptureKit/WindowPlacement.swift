import CoreGraphics

/// Where an app window opens, and what it remembers when it closes.
///
/// Every window opens exactly centred on the screen the user is working on (AppKit's own
/// `NSWindow.center()` puts it about a third of the way down instead). Resizable windows also come
/// back the way the last one was closed: at the same size, filling the screen, or in macOS full
/// screen. The app stores a `Memo` per window kind; this type is the pure maths around it.
public enum WindowPlacement {
    public enum Mode: String, Codable, Equatable {
        case normal
        /// Covering the whole visible screen (zoomed / Fill, or dragged to the edges), but not in
        /// macOS full screen.
        case fill
        /// macOS full screen (the green button), in its own Space.
        case fullScreen
    }

    /// What is remembered about a window kind, in points.
    public struct Memo: Codable, Equatable {
        /// The window's frame size outside full screen — the size it returns to on leaving it.
        public var width: Double
        public var height: Double
        public var mode: Mode

        public init(width: Double, height: Double, mode: Mode) {
            self.width = width
            self.height = height
            self.mode = mode
        }
    }

    /// A window within this many points of the visible screen's size on both axes counts as
    /// filling it (windows snap to whole points, and some can't shrink their title bar away).
    static let fillTolerance: CGFloat = 8

    /// A frame of `size` centred in `visible` (the screen minus the menu bar and Dock), shrunk to
    /// fit inside it, on whole points.
    public static func centred(_ size: CGSize, in visible: CGRect) -> CGRect {
        let w = min(size.width, visible.width)
        let h = min(size.height, visible.height)
        return CGRect(x: (visible.midX - w / 2).rounded(), y: (visible.midY - h / 2).rounded(),
                      width: w, height: h)
    }

    /// The frame to open a window at, and whether to put it into full screen once it's on screen.
    /// With nothing remembered it opens at `defaultSize`; a `.fill` window covers `visible`; a
    /// full-screen window gets the centred frame it will return to on leaving full screen.
    /// Remembered sizes never go below `minSize`.
    public static func opening(remembered: Memo?, defaultSize: CGSize, minSize: CGSize,
                               visible: CGRect) -> (frame: CGRect, enterFullScreen: Bool) {
        guard let memo = remembered, memo.width > 0, memo.height > 0 else {
            return (centred(defaultSize, in: visible), false)
        }
        if memo.mode == .fill { return (visible, false) }
        let size = CGSize(width: max(CGFloat(memo.width), minSize.width),
                          height: max(CGFloat(memo.height), minSize.height))
        return (centred(size, in: visible), memo.mode == .fullScreen)
    }

    /// What to remember as a window closes. `normalSize` is its frame size from just before it
    /// entered full screen (nil if it never did); `visible` is its screen's visible frame.
    public static func memo(frameSize: CGSize, normalSize: CGSize?, isFullScreen: Bool,
                            visible: CGRect) -> Memo {
        if isFullScreen {
            let s = normalSize ?? frameSize
            return Memo(width: Double(s.width), height: Double(s.height), mode: .fullScreen)
        }
        let fills = frameSize.width >= visible.width - fillTolerance
            && frameSize.height >= visible.height - fillTolerance
        return Memo(width: Double(frameSize.width), height: Double(frameSize.height),
                    mode: fills ? .fill : .normal)
    }
}
