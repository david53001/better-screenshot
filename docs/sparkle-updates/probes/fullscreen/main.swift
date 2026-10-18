import AppKit
// Process B: an accessory app (like BetterScreenshot) evaluating the shipped rule,
// CaptureKit's LaunchAtLoginPrompt.fullScreenInFront, exactly as LaunchAtLoginPromptController does.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
func spin(_ s: TimeInterval) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        if let e = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) { app.sendEvent(e) }
    }
}
func evaluate() -> (Bool, String) {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let windows = list.compactMap { info -> LaunchAtLoginPrompt.WindowInfo? in
        guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let layer = info[kCGWindowLayer as String] as? Int,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
        return .init(ownerPID: pid, layer: layer, bounds: bounds)
    }
    let front = NSWorkspace.shared.frontmostApplication
    let screens = NSScreen.screens.map { LaunchAtLoginPrompt.Screen(frame: $0.frame, topInset: $0.safeAreaInsets.top) }
    let mine = windows.filter { $0.ownerPID == front?.processIdentifier && $0.layer >= 0 }
        .map { "L\($0.layer) \(Int($0.bounds.minX)),\(Int($0.bounds.minY)) \(Int($0.bounds.width))x\(Int($0.bounds.height))" }
    return (LaunchAtLoginPrompt.fullScreenInFront(frontmostPID: front?.processIdentifier, windows: windows, screens: screens),
            "\(front?.localizedName ?? "nil"): \(mine.prefix(4).joined(separator: " | "))")
}
let s = NSScreen.screens.map { "\($0.frame) inset \($0.safeAreaInsets.top)" }
print("B screens:", s); fflush(stdout)
// The screen may be locked (then loginwindow is frontmost): also read A's own windows from the
// full list and evaluate the rule as if A were frontmost.
func evaluateA() -> String {
    guard let a = NSWorkspace.shared.runningApplications.first(where: { $0.executableURL?.lastPathComponent == "probe-a" }) else { return "A not running" }
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let windows = list.compactMap { info -> LaunchAtLoginPrompt.WindowInfo? in
        guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == a.processIdentifier,
              let layer = info[kCGWindowLayer as String] as? Int,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
        return .init(ownerPID: pid, layer: layer, bounds: bounds)
    }
    let screens = NSScreen.screens.map { LaunchAtLoginPrompt.Screen(frame: $0.frame, topInset: $0.safeAreaInsets.top) }
    let fs = LaunchAtLoginPrompt.fullScreenInFront(frontmostPID: a.processIdentifier, windows: windows, screens: screens)
    let desc = windows.filter { $0.layer >= 0 && $0.bounds.width > 100 }.map { "L\($0.layer) \(Int($0.bounds.minX)),\(Int($0.bounds.minY)) \(Int($0.bounds.width))x\(Int($0.bounds.height))" }
    return "A-as-front fullScreenInFront \(fs): \(desc.joined(separator: " | "))"
}
for i in 0..<28 {
    spin(0.5)
    let (fs, detail) = evaluate()
    print(String(format: "B t=%.1f", Double(i + 1) / 2), "fullScreenInFront", fs, "front", detail, "||", evaluateA()); fflush(stdout)
}
