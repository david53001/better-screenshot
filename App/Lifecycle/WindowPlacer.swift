import AppKit
import CaptureKit

/// Opens the app's windows exactly centred on the screen under the pointer. Resizable windows
/// given a `rememberAs` key also open the way the last window of that kind was closed — same size,
/// covering the whole screen, or in macOS full screen (maths in CaptureKit's `WindowPlacement`;
/// stored in UserDefaults as `windowPlacement.<key>`).
///
/// Every window opens on the Space (desktop) the user is on — Settings and Welcome also over an app in full
/// screen — instead of macOS switching them to the desktop where the window was last (owner, 2026-09-30:
/// "open it in your current page"). One still open on another desktop is brought here, re-centred under
/// the pointer.
///
/// Call `place` right before showing a window. A window already on screen on this desktop is left where it is.
@MainActor
enum WindowPlacer {
    /// One per remembered window, alive until that window closes.
    private static var trackers: [ObjectIdentifier: Tracker] = [:]

    static func place(_ window: NSWindow, rememberAs key: String? = nil) {
        // `.moveToActiveSpace`: ordering it front moves it to the current desktop rather than switching
        // desktops. `.fullScreenAuxiliary` (it may show on top of a full-screen app's Space) only for the
        // fixed-size windows: the remembered ones can go full screen themselves (`.fullScreenPrimary`),
        // and AppKit doesn't define both at once.
        window.collectionBehavior.insert(.moveToActiveSpace)
        if key == nil { window.collectionBehavior.insert(.fullScreenAuxiliary) }
        if window.isVisible {
            // Open on another desktop (and not a full-screen window, which is its own Space): it comes to
            // this one as the caller orders it front — centre it on the screen the user is looking at.
            if !window.isOnActiveSpace, !window.styleMask.contains(.fullScreen) {
                window.setFrame(WindowPlacement.centred(window.frame.size, in: screenUnderPointer().visibleFrame),
                                display: false)
            }
            return
        }
        let visible = screenUnderPointer().visibleFrame
        guard let key else {
            window.setFrame(WindowPlacement.centred(window.frame.size, in: visible), display: false)
            return
        }
        let opening = WindowPlacement.opening(remembered: load(key), defaultSize: window.frame.size,
                                              minSize: minFrameSize(of: window), visible: visible)
        window.setFrame(opening.frame, display: false)
        window.collectionBehavior.insert(.fullScreenPrimary)
        trackers[ObjectIdentifier(window)] = Tracker(window: window, key: key)
        if opening.enterFullScreen {
            // The caller shows the window later in this same run-loop turn; full screen needs it up.
            DispatchQueue.main.async { [weak window] in
                guard let window, window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
        }
    }

    private static func screenUnderPointer() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func minFrameSize(of window: NSWindow) -> CGSize {
        let fromContent = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size
        return CGSize(width: max(window.minSize.width, fromContent.width),
                      height: max(window.minSize.height, fromContent.height))
    }

    private static func defaultsKey(_ key: String) -> String { "windowPlacement.\(key)" }

    private static func load(_ key: String) -> WindowPlacement.Memo? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(key)) else { return nil }
        return try? JSONDecoder().decode(WindowPlacement.Memo.self, from: data)
    }

    fileprivate static func save(_ memo: WindowPlacement.Memo, as key: String) {
        guard let data = try? JSONEncoder().encode(memo) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey(key))
    }

    fileprivate static func stopTracking(_ window: NSWindow) {
        trackers[ObjectIdentifier(window)] = nil
    }

    /// Remembers one window's size from before full screen, and saves its state as it closes.
    @MainActor private final class Tracker {
        private weak var window: NSWindow?
        private let key: String
        private var normalSize: CGSize?
        private var observers: [NSObjectProtocol] = []

        init(window: NSWindow, key: String) {
            self.window = window
            self.key = key
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification,
                                                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.normalSize = self?.window?.frame.size }
            })
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.normalSize = nil }
            })
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowWillClose() }
            })
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        private func windowWillClose() {
            guard let window else { return }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            let memo = WindowPlacement.memo(frameSize: window.frame.size, normalSize: normalSize,
                                            isFullScreen: window.styleMask.contains(.fullScreen),
                                            visible: visible)
            WindowPlacer.save(memo, as: key)
            WindowPlacer.stopTracking(window)
        }
    }
}
