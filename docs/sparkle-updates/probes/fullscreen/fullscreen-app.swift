import AppKit
// Process A: a normal window, then zoomed, then real full screen for 4 s, then back.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
let previous = NSWorkspace.shared.frontmostApplication
func spin(_ s: TimeInterval) {
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        if let e = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) { app.sendEvent(e) }
    }
}
let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 300), styleMask: [.titled, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false)
win.collectionBehavior = [.fullScreenPrimary]
win.title = "fs-probe-A"
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
spin(1.5)
print("A: normal", win.frame); fflush(stdout)
win.zoom(nil)
spin(2.0)
print("A: zoomed", win.frame); fflush(stdout)
win.zoom(nil)
spin(1.0)
print("A: entering full screen"); fflush(stdout)
win.toggleFullScreen(nil)
spin(4.0)
print("A: leaving full screen", win.frame); fflush(stdout)
win.toggleFullScreen(nil)
spin(1.5)
win.close()
previous?.activate()
spin(0.5)
print("A: done"); fflush(stdout)
