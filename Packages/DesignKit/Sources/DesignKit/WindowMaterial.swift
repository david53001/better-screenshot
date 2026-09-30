import AppKit
import Combine
import SwiftUI

/// A window's translucent backdrop: a behind-window `.popover` material (MacStats' popover family)
/// that follows the window's active state (dims when inactive, like System Settings), under a
/// window-background-colour layer whose alpha follows Settings → Opacity (`OpacityCurve.windowSolid`:
/// 0.15 at 0, 0.52 at the default, solid at 1).
public enum WindowMaterial {
    public static func make() -> NSVisualEffectView {
        WindowBackdropView()
    }

    /// Puts `content` inside a material backdrop and makes it the window's content view.
    @MainActor public static func install(_ content: NSView, in window: NSWindow) {
        let backdrop = make()
        backdrop.frame = content.frame
        content.frame = backdrop.bounds
        content.autoresizingMask = [.width, .height]
        backdrop.addSubview(content)
        window.contentView = backdrop
    }
}

final class WindowBackdropView: NSVisualEffectView {
    /// The window-background colour over the material; the bottom-most subview, so content added
    /// later lands above it.
    let solid = SolidFillView()
    private var opacityWatch: AnyCancellable?

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        solid.frame = bounds
        solid.autoresizingMask = [.width, .height]
        addSubview(solid)
        opacityWatch = UIOpacity.shared.$value.sink { [weak self] in
            self?.solid.alpha = OpacityCurve.windowSolid($0)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// `windowBackgroundColor` at `alpha`, re-resolved when the appearance changes. Never takes clicks.
final class SolidFillView: NSView {
    var alpha: Double = 0 {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
