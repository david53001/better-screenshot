import AppKit
import SwiftUI

/// A window's translucent backdrop: a behind-window `NSVisualEffectView` that follows
/// the window's active state (dims when inactive, like System Settings).
public enum WindowMaterial {
    public static func make(_ material: NSVisualEffectView.Material = .sidebar) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    /// Puts `content` inside a material backdrop and makes it the window's content view.
    @MainActor public static func install(_ content: NSView, in window: NSWindow,
                                          material: NSVisualEffectView.Material = .sidebar) {
        let backdrop = make(material)
        backdrop.frame = content.frame
        content.frame = backdrop.bounds
        content.autoresizingMask = [.width, .height]
        backdrop.addSubview(content)
        window.contentView = backdrop
    }
}
