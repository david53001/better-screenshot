#if SPARKLE_E2E_TEST
import AppKit

/// Only in the throwaway build of `scripts/sparkle-e2e-test.sh` (`-DSPARKLE_E2E_TEST`), and only
/// with `E2E_UI=1` (the script sets `SPARKLE_E2E_UI=1` for the OLD copy, which has no
/// `SUAutomaticallyUpdate`): goes through Sparkle's real windows the way a user does, so the
/// production UI path is tested, not just the automatic install.
///
/// After a scheduled check found an update (gentle reminders: `Updates.standardUserDriverWillHandleShowingUpdate`
/// set `pendingVersion` and called `start`):
/// 1. waits for Sparkle's update window, logs whether it took focus (it must not) and the menu
///    title (`Updates.actionTitle`, "Update Available (X)…"), saves a snapshot;
/// 2. does what that menu item does (`Updates.showSparkleWindow`, without activating the app) and
///    logs `pendingVersion` afterwards (Sparkle's "user attention" callback clears it);
/// 3. clicks **Install Update**, waits for **Install and Relaunch**, saves a snapshot, clicks it.
///    Sparkle installs and relaunches; the script checks the installed build.
///
/// Every window of the test app is made fully transparent as soon as it appears, so nothing shows
/// on the screen of the person running the test; snapshots are drawn from the views
/// (`cacheDisplay`), so they need no Screen Recording permission. Log lines start "SPARKLE-E2E UI".
@MainActor
enum SparkleE2EUI {
    nonisolated static let isOn = ProcessInfo.processInfo.environment["SPARKLE_E2E_UI"] == "1"
    private static let snapshotDir = ProcessInfo.processInfo.environment["SPARKLE_E2E_SNAP_DIR"]
    private static let timeout: TimeInterval = 120

    private static var timer: Timer?
    private static var stage = 0
    private static var startedAt = Date()
    private static var stageStartedAt = Date()

    static func start() {
        guard isOn, timer == nil else { return }
        startedAt = Date()
        stageStartedAt = startedAt
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in MainActor.assumeIsolated { step() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func log(_ line: String) { NSLog("SPARKLE-E2E UI %@", line) }

    private static func next() {
        stage += 1
        stageStartedAt = Date()
    }

    private static func step() {
        for window in NSApp.windows where window.isVisible && window.alphaValue > 0 { window.alphaValue = 0 }
        guard Date().timeIntervalSince(startedAt) < timeout else {
            log("timed out at stage \(stage)")
            timer?.invalidate()
            return
        }
        switch stage {
        case 0:
            guard let (window, _) = find("Install Update") else { return }
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            log("update window shown: key \(window.isKeyWindow ? 1 : 0), app active \(NSApp.isActive ? 1 : 0), frontmost app \(front)")
            log("menu title: \(Updates.shared.actionTitle)")
            snapshot(window, "1-update-found")
            Updates.shared.showSparkleWindow()   // the menu item's action, minus activating the app
            next()
        case 1:
            // Sparkle's "user attention" callback clears pendingVersion asynchronously.
            guard Date().timeIntervalSince(stageStartedAt) > 1 else { return }
            log("after the menu action: pending \(Updates.shared.pendingVersion ?? "none"), menu title: \(Updates.shared.actionTitle)")
            guard let (_, button) = find("Install Update") else { return }
            log("clicking Install Update")
            button.performClick(nil)
            next()
        case 2:
            guard let (window, button) = find("Install and Relaunch") else { return }
            snapshot(window, "2-ready-to-install")
            log("clicking Install and Relaunch")
            button.performClick(nil)
            next()
            timer?.invalidate()
        default:
            break
        }
    }

    /// The first visible window with an enabled button titled `title`.
    private static func find(_ title: String) -> (NSWindow, NSButton)? {
        func search(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == title, button.isEnabled, !button.isHiddenOrHasHiddenAncestor {
                return button
            }
            for sub in view.subviews { if let found = search(sub) { return found } }
            return nil
        }
        for window in NSApp.windows where window.isVisible {
            if let content = window.contentView, let button = search(content) { return (window, button) }
        }
        return nil
    }

    private static func snapshot(_ window: NSWindow, _ name: String) {
        guard let snapshotDir, let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: snapshotDir).appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(atPath: snapshotDir, withIntermediateDirectories: true)
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            log("snapshot \(url.path)")
        } catch {
            log("snapshot failed: \(error)")
        }
    }
}
#endif
