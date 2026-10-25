import AppKit

// Plain AppKit lifecycle. The SwiftUI App existed only for its Settings scene,
// whose opener (private showSettingsWindow: selector) macOS 14 broke for
// LSUIElement apps (the app was one until 3.3.0) — SettingsWindowController owns
// the window instead, and MenuBarController builds the main menu.
@main
@MainActor
enum Main {
    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
